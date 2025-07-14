package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"io"
	"net/http"
	"net/http/httptest"
	"reflect"
	"testing"
	"time"

	"github.com/alexliesenfeld/health"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/config"
)

func mockRabbitmqCheck(_ *config.Config, _ logger.ILogger) health.Check {
	return health.Check{
		Name: "testCheck",
		Check: func(ctx context.Context) error {
			return nil // replace with your desired mock behavior
		},
	}
}

func SetUpRouter() *gin.Engine {
	router := gin.Default()
	return router
}

func TestDefaultHandler(t *testing.T) {
	mockResponse := `{"message": "tdp-notifications api running..."}`
	r := SetUpRouter()

	r.GET("/", DefaultHandler())
	request, _ := http.NewRequest("GET", "/", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, request)

	response, _ := io.ReadAll(w.Body)

	assert.JSONEq(t, mockResponse, string(response))
	assert.Equal(t, http.StatusOK, w.Code)
}

func TestHealthCheckHandler(t *testing.T) {
	r := SetUpRouter()

	CheckFunctions = []checkFunc{
		mockRabbitmqCheck,
	}
	cfg := config.Config{}
	cfg.HealthCheck.Frequency = 1

	r.GET("/health/", HealthCheckHandler(&cfg, &logger.MockLogger{}))

	// so we wait for the check to get triggerred
	time.Sleep(time.Millisecond)

	req, err := http.NewRequest("GET", "/health/", nil)
	if err != nil {
		t.Fatal(err)
	}

	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	response, _ := io.ReadAll(w.Body)

	expectedBody := HealthCheckResponse{
		Name:   "Self Check",
		Status: "Healthy",
		Details: []HealthCheckResponseItem{
			{
				Key:    "testCheck",
				Status: "Healthy",
			},
		},
	}
	res := HealthCheckResponse{}
	_ = json.Unmarshal(response, &res)
	assert.Equal(t, expectedBody, res)
}

func TestHealthCheckParseStatusType(t *testing.T) {
	testCases := []struct {
		checkerStatus     health.AvailabilityStatus
		healthCheckStatus string
	}{
		{
			health.StatusUp,
			"Healthy",
		},
		{
			health.StatusDown,
			"Unhealthy",
		},
		{
			health.StatusUnknown,
			"Unknown",
		},
	}
	for _, tc := range testCases {
		st := parseStatusType(tc.checkerStatus)
		assert.Equal(t, st, tc.healthCheckStatus)
	}
}

func TestHealthCheckParseResonse(t *testing.T) {
	err := errors.New("Fake error")
	SkipOnErr["TestSkipError"] = true
	testCases := []struct {
		expectedResponse    HealthCheckResponse
		healthCheckerResult health.CheckerResult
	}{
		{
			HealthCheckResponse{Name: "Self Check", Status: "Healthy"},
			health.CheckerResult{Status: health.StatusUp},
		},
		{
			HealthCheckResponse{Name: "Self Check", Status: "Healthy", Details: []HealthCheckResponseItem{
				{Key: "Test", Status: "Healthy"},
			}},
			health.CheckerResult{Status: health.StatusUp, Details: map[string]health.CheckResult{
				"Test": {Status: health.StatusUp},
			}},
		},
		{
			HealthCheckResponse{Name: "Self Check", Status: "Unhealthy", Details: []HealthCheckResponseItem{
				{Key: "Test", Status: "Unhealthy", Error: "Fake error"},
			}},
			health.CheckerResult{Status: health.StatusDown, Details: map[string]health.CheckResult{
				"Test": {
					Status: health.StatusDown,
					Error:  err,
				},
			}},
		},
		{
			HealthCheckResponse{Name: "Self Check", Status: "Healthy", Details: []HealthCheckResponseItem{
				{Key: "TestSkipError", Status: "Unhealthy", Error: "Fake error"},
			}},
			health.CheckerResult{Status: health.StatusUp, Details: map[string]health.CheckResult{
				"TestSkipError": {
					Status: health.StatusDown,
					Error:  err,
				},
			}},
		},
	}
	for _, tc := range testCases {
		parsedResponse := parseResponse(&tc.healthCheckerResult)
		if !reflect.DeepEqual(parsedResponse, tc.expectedResponse) {
			t.Errorf("parseRequest result is not as expected. Got: %v, Want: %v", parsedResponse, tc.expectedResponse)
		}
	}
}

func TestHandlerResponseWriter(t *testing.T) {
	result := &health.CheckerResult{
		Status: health.StatusUp,
	}

	handlerWriter := HandlerResponseWriter{}

	w := httptest.NewRecorder()

	err := handlerWriter.Write(result, http.StatusOK, w, nil)
	assert.NoError(t, err)

	header := w.Header()
	expectedHeader := "application/json; charset=utf-8"
	assert.Equal(t, expectedHeader, header.Get("Content-Type"), "Content-Type header")

	expectedBody := `{"name":"Self Check","status":"Healthy","details":null}`
	assert.Equal(t, expectedBody, w.Body.String(), "response body")
}
