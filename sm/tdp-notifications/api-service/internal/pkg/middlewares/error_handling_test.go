package middlewares

import (
	"errors"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/lpar/problem"
	"github.com/stretchr/testify/assert"
)

type ProblemDetailsResponse struct {
	Status        int                 `json:"status"`
	Detail        string              `json:"detail"`
	Type          string              `json:"type"`
	InvalidParams []map[string]string `json:"invalid-params"`
}

type ValidationTest struct {
	RequiredField        string `json:"required_field" validate:"required"`
	EmailField           string `json:"email_field" validate:"omitempty,email"`
	GreaterThanOrEqual   int    `json:"greater_than_or_equal" validate:"omitempty,gte=10"`
	LessThanOrEqual      int    `json:"less_than_or_equal" validate:"omitempty,lte=20"`
	DatetimeField        string `json:"datetime_field" validate:"omitempty,datetime=2006-01-02"`
	E164Phone            string `json:"e164_phone" validate:"omitempty,e164"`
	BooleanField         string `json:"boolean_field" validate:"omitempty,boolean"`
	Iso3166Alpha2Country string `json:"iso3166_alpha2_country" validate:"omitempty,iso3166_1_alpha2"`
	FqdnField            string `json:"fqdn_field" validate:"omitempty,fqdn"`
	IPv4Field            string `json:"ipv4_field" validate:"omitempty,ipv4"`
	IPv6Field            string `json:"ipv6_field" validate:"omitempty,ipv6"`
	UnknownField         string `json:"unknown_field" validate:"omitempty,json"`
	RequiredWithoutField string `json:"required_without_field" validate:"required_without=UnknownField"`
	ExcludedWithField    string `json:"excluded_with_field" validate:"excluded_with=UnknownField"`
}

func TestErrorHandlingMiddleware(t *testing.T) {
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)

	c.Error(errors.New("test error"))

	ErrorHandling(&logger.MockLogger{})(c)

	resp := w.Result()
	body, _ := io.ReadAll(resp.Body)
	assert.Equal(t, http.StatusInternalServerError, resp.StatusCode)
	assert.Equal(t, "application/problem+json", resp.Header.Get("Content-Type"))
	assert.Contains(t, string(body), "test error")
}

func TestErrorHandlingMiddlewareUnhandled(t *testing.T) {
	router := gin.New()
	router.Use(ErrorHandling(&logger.MockLogger{}))

	router.GET("/panic", func(c *gin.Context) {
		panic("Something went wrong!")
	})

	req, err := http.NewRequest("GET", "/panic", nil)
	if err != nil {
		t.Fatalf("Failed to create request: %v", err)
	}

	rec := httptest.NewRecorder()

	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Errorf("Expected status code %v, but got %v", http.StatusInternalServerError, rec.Code)
	}

}

func TestErrorHandlingMiddlewareValidationProblem(t *testing.T) {
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)

	err := &problem.ValidationProblem{
		ProblemDetails: problem.ProblemDetails{
			Type:   "https://example.com/validation-error",
			Title:  "Validation Error",
			Status: http.StatusBadRequest,
			Detail: "Validation failed",
		},
		ValidationErrors: []problem.ValidationError{
			{FieldName: "username", Error: "cannot be blank"},
			{FieldName: "email", Error: "must be a valid email"},
		},
	}
	c.Error(err)

	ErrorHandling(&logger.MockLogger{})(c)

	resp := w.Result()
	body, _ := io.ReadAll(resp.Body)
	assert.Equal(t, http.StatusBadRequest, resp.StatusCode)
	assert.Equal(t, "application/problem+json", resp.Header.Get("Content-Type"))
	assert.Contains(t, string(body), "Validation Error")
	assert.Contains(t, string(body), "username")
	assert.Contains(t, string(body), "cannot be blank")
	assert.Contains(t, string(body), "email")
	assert.Contains(t, string(body), "must be a valid email")
}

func TestErrorHandlingMiddlewareOtherErrors(t *testing.T) {
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)

	c.Error(errors.New("test error"))

	ErrorHandling(&logger.MockLogger{})(c)

	resp := w.Result()
	body, _ := io.ReadAll(resp.Body)
	assert.Equal(t, http.StatusInternalServerError, resp.StatusCode)
	assert.Equal(t, "application/problem+json", resp.Header.Get("Content-Type"))
	assert.Contains(t, string(body), "test error")
}

func TestCreateInternalServerProblemDetails(t *testing.T) {
	expectedDetail := "Test problem detail"
	expectedStatusCode := http.StatusInternalServerError
	expectedType := "https://www.rfc-editor.org/rfc/rfc7231#section-6.6.1"

	pd := createInternalServerProblemDetails(expectedDetail)

	assert.Equal(t, expectedDetail, pd.Detail)
	assert.Equal(t, expectedStatusCode, pd.Status)
	assert.Equal(t, expectedType, pd.Type)
}
