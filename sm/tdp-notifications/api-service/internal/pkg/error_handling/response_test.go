package error_handling_test

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/error_handling"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/middlewares"
	"github.com/tucowsinc/tdp-shared-go/logger"

	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"
	"github.com/stretchr/testify/assert"

	tcwire "github.com/tucowsinc/tdp-messages-go/message"
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

func TestHandleMessageBusErrorResponse(t *testing.T) {
	testCases := []struct {
		appCode      tcwire.ErrorResponse_AppErrorCode
		expectedCode int
	}{
		{tcwire.ErrorResponse_NOT_FOUND, http.StatusNotFound},
		{tcwire.ErrorResponse_ALREADY_EXISTS, http.StatusInternalServerError},
		{tcwire.ErrorResponse_UNKNOWN, http.StatusInternalServerError},
		{tcwire.ErrorResponse_FAILED_PRECONDITION, http.StatusUnprocessableEntity},
		{tcwire.ErrorResponse_BAD_REQUEST, http.StatusBadRequest},
	}

	for _, tc := range testCases {
		t.Run(fmt.Sprintf("appCode=%v,expectedCode=%v,expectedError=%v", tc.appCode, tc.expectedCode, ""), func(t *testing.T) {
			context, _ := gin.CreateTestContext(httptest.NewRecorder())
			errResponse := &tcwire.ErrorResponse{
				Code:    tcwire.ErrorResponse_SERVICE_FAILURE,
				AppCode: tc.appCode,
				Message: "",
				Details: "",
			}
			error_handling.HandleMessageBusErrorResponse(context, &logger.MockLogger{}, errResponse)
			assert.Equal(t, tc.expectedCode, context.Writer.Status())
		})
	}
}

func TestValidationError(t *testing.T) {

	testCases := []struct {
		testStruct      ValidationTest
		validationField string
	}{
		{
			ValidationTest{RequiredWithoutField: "RequiredWithoutField"},
			"ValidationTest.RequiredField",
		},
		{
			ValidationTest{RequiredField: "Required", EmailField: "email@example"},
			"ValidationTest.EmailField",
		},
		{
			ValidationTest{RequiredField: "Required", GreaterThanOrEqual: 5},
			"ValidationTest.GreaterThanOrEqual",
		},
		{
			ValidationTest{RequiredField: "Required", LessThanOrEqual: 30},
			"ValidationTest.LessThanOrEqual",
		},
		{
			ValidationTest{RequiredField: "Required", DatetimeField: "2030/03/03"},
			"ValidationTest.DatetimeField",
		},
		{
			ValidationTest{RequiredField: "Required", E164Phone: "1234567890"},
			"ValidationTest.E164Phone",
		},
		{
			ValidationTest{RequiredField: "Required", Iso3166Alpha2Country: "USA"},
			"ValidationTest.Iso3166Alpha2Country",
		},
		{
			ValidationTest{RequiredField: "Required", FqdnField: "example"},
			"ValidationTest.FqdnField",
		},
		{
			ValidationTest{RequiredField: "Required", IPv4Field: "192.0.2.300"},
			"ValidationTest.IPv4Field",
		},
		{
			ValidationTest{RequiredField: "Required", IPv6Field: "2001:0db8:85a3:0000:0000:8a2e:0370:7334:abcd"},
			"ValidationTest.IPv6Field",
		},
		{
			ValidationTest{RequiredField: "Required", BooleanField: "a"},
			"ValidationTest.BooleanField",
		},
		{
			ValidationTest{RequiredField: "Required", UnknownField: "a"},
			"ValidationTest.UnknownField",
		},
		{
			ValidationTest{RequiredField: "Required"},
			"ValidationTest.RequiredWithoutField",
		},
		{
			ValidationTest{UnknownField: "UnknownField", ExcludedWithField: "ExcludedWithField"},
			"ValidationTest.ExcludedWithField",
		},
	}

	for _, tc := range testCases {
		fmt.Println(tc)

		req, err := http.NewRequest("GET", "/", nil)
		if err != nil {
			t.Fatal(err)
		}

		w := httptest.NewRecorder()

		r := gin.Default()
		r.Use(middlewares.ErrorHandling(&logger.MockLogger{}))

		r.GET("/", func(c *gin.Context) {
			validate := validator.New()
			ve := validate.Struct(tc.testStruct)

			if ve != nil {
				error_handling.ValidationErrorResponse("", ve.(validator.ValidationErrors), c)
				return
			}

			error_handling.BadRequestErrorResponse("", c)
			return
		})

		r.ServeHTTP(w, req)
		res := w.Result()
		defer res.Body.Close()

		data, _ := io.ReadAll(res.Body)

		resData := &ProblemDetailsResponse{}

		err = json.Unmarshal([]byte(data), &resData)
		assert.Nilf(t, err, "Failed to parse response body: %v", err)

		foundVal := false

		for _, v := range resData.InvalidParams {
			if v["name"] == tc.validationField {
				foundVal = true
				break
			}
		}

		assert.True(t, foundVal)
	}
}
