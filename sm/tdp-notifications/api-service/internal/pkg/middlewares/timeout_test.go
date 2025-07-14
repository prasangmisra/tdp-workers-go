package middlewares

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/lpar/problem"
	"github.com/stretchr/testify/assert"
)

func SetUpRouter() *gin.Engine {
	router := gin.Default()
	return router
}

type header struct {
	Key   string
	Value string
}

func PerformRequest(r http.Handler, method, path string, headers ...header) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, nil)
	for _, h := range headers {
		req.Header.Add(h.Key, h.Value)
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func TestTimeOutMiddleware_TimeoutContext(t *testing.T) {
	hasTimeoutContext := false

	router := SetUpRouter()
	router.Use(TimeOut())
	router.GET("/", func(ctx *gin.Context) {
		requestCtx := ctx.Request.Context()
		_, hasTimeoutContext = requestCtx.Deadline()
	})

	header := header{
		Key:   "x-timeout",
		Value: "30",
	}

	PerformRequest(router, http.MethodGet, "/", header)
	assert.True(t, hasTimeoutContext)
}

func TestTimeoutMiddleware_SetsTimeout(t *testing.T) {
	tests := []struct {
		testName          string
		timeoutFromHeader int
		lowerBound        int
	}{
		{
			testName:          "Default",
			timeoutFromHeader: DefaultTimeoutInSec,
			lowerBound:        DefaultTimeoutInSec - 1,
		},
		{
			testName:          "ValidCustomTimeout",
			timeoutFromHeader: 40,
			lowerBound:        39,
		},
	}

	for _, tt := range tests {
		t.Run(tt.testName, func(t *testing.T) {
			var timeRemaining time.Duration
			router := SetUpRouter()
			router.Use(TimeOut())
			router.GET("/", func(ctx *gin.Context) {
				requestCtx := ctx.Request.Context()

				deadline, _ := requestCtx.Deadline()

				timeRemaining = time.Until(deadline)
			})

			//this part is tricky since we start approaching the deadline as soon as the context is
			//created, so there will be some delta between what we set and what the value is when
			//we check , therefore allow for some margin of error
			if tt.timeoutFromHeader == DefaultTimeoutInSec {
				PerformRequest(router, http.MethodGet, "/")
				assert.True(t, time.Duration(tt.lowerBound)*time.Second < timeRemaining && timeRemaining < time.Duration(DefaultTimeoutInSec)*time.Second)
			} else {
				header := header{
					Key:   "x-timeout",
					Value: strconv.Itoa(tt.timeoutFromHeader),
				}
				PerformRequest(router, http.MethodGet, "/", header)
				assert.True(t, time.Duration(tt.lowerBound)*time.Second < timeRemaining && timeRemaining < time.Duration(tt.timeoutFromHeader)*time.Second)
			}

		})
	}
}

func TestTimeOutMiddleware_MinimumAcceptedTimeout(t *testing.T) {
	router := SetUpRouter()
	router.Use(TimeOut())
	router.GET("/", func(ctx *gin.Context) {
		_ = ctx.Request.Context()
	})

	header := header{
		Key:   "x-timeout",
		Value: "2",
	}

	r := PerformRequest(router, http.MethodGet, "/", header)

	data, err := io.ReadAll(r.Body)
	assert.Nilf(t, err, "Failed to read response body: %v", err)

	resData := problem.ProblemDetails{}
	err = json.Unmarshal(data, &resData)
	assert.Nilf(t, err, "Failed to parse response body: %v", err)

	assert.Equal(t, http.StatusBadRequest, resData.Status)
	assert.Equal(t, fmt.Sprintf("x-timeout must be %v or greater.", MinTimeoutInSec), resData.Detail)
}
