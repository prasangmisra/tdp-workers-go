package error_handling

import (
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"
	"github.com/lpar/problem"
	tcwire "github.com/tucowsinc/tdp-messages-go/message"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/validators"
	"github.com/tucowsinc/tdp-shared-go/logger"
)

// BadRequestErrorResponse ends the current request setting the status code to 400 with the provided error message.
// The returned response is of type ProblemDetails (RFC-7807, RFC-7231)
func BadRequestErrorResponse(message string, context *gin.Context) {
	if message == "" {
		message = "invalid or bad request"
	}

	response := problem.New(http.StatusBadRequest).WithDetail(message)
	response.Type = "https://tools.ietf.org/html/rfc7231#section-6.5.1"

	_ = context.AbortWithError(http.StatusBadRequest, response)

	return
}

// InternalServerErrorResponse ends the current request setting the status code to 500 with the provided error message.
// The returned response is of type ProblemDetails (RFC-7807, RFC-7231)
func InternalServerErrorResponse(message string, log logger.ILogger, context *gin.Context) {
	if message == "" {
		message = " unhandled error encountered while processing the request"
	}

	response := problem.New(http.StatusInternalServerError).WithDetail(message)
	response.Type = "https://www.rfc-editor.org/rfc/rfc7231#section-6.6.1"

	err := context.AbortWithError(http.StatusInternalServerError, response)
	log.Error("error response", logger.Fields{"error": err})
	return
}

// NotFoundErrorResponse ends the current request setting the status code to 404 with the provided error message.
// The returned response is of type ProblemDetails (RFC-7807, RFC-7231)
func NotFoundErrorResponse(message string, context *gin.Context) {
	if message == "" {
		message = "request resource was not found"
	}

	response := problem.New(http.StatusNotFound).WithDetail(message)
	response.Type = "https://tools.ietf.org/html/rfc7231#section-6.5.4"

	_ = context.AbortWithError(http.StatusNotFound, response)
	return
}

// UnprocessableEntityErrorResponse ends the current request setting the status code to 422 with the provided error message.
// The returned response is of type ProblemDetails (RFC-4918)
func UnprocessableEntityErrorResponse(message string, context *gin.Context) {
	if message == "" {
		message = "request could not be processed"
	}

	response := problem.New(http.StatusUnprocessableEntity).WithDetail(message)
	response.Type = "https://www.rfc-editor.org/rfc/rfc4918#section-11.2"

	_ = context.AbortWithError(http.StatusUnprocessableEntity, response)
	return
}

// ValidationErrorResponse ends the current request setting the status code to 400 with the provided error message.
// The returned response is of type ValidationProblem (RFC-7807, RFC-7231) and contains the validation errors with
// field names and the associated error message for each field
func ValidationErrorResponse(message string, errors validator.ValidationErrors, context *gin.Context) {
	if message == "" {
		message = "one or more validation errors occurred while processing the request"
	}

	response := problem.NewValidationProblem()
	response.Detail = message
	response.Type = "https://tools.ietf.org/html/rfc7231#section-6.5.1"

	for _, fe := range errors {
		response.ValidationErrors = append(response.ValidationErrors, problem.ValidationError{
			FieldName: fe.StructNamespace(),
			Error:     getValidationErrorMessage(fe),
		})
	}

	_ = context.AbortWithError(http.StatusBadRequest, response)
	return
}

func RequestTimeoutResponse(message string, context *gin.Context) {
	response := problem.New(http.StatusRequestTimeout).WithDetail(message)
	response.Type = "https://tools.ietf.org/html/rfc7231#section-6.5.7"

	_ = context.AbortWithError(http.StatusRequestTimeout, response)

	return
}

func getValidationErrorMessage(fe validator.FieldError) (errorMessage string) {
	switch fe.Tag() {
	case "required":
		return fmt.Sprintf("%v is a required field", fe.Field())
	case "email":
		return fmt.Sprintf("%v is not a valid email", fe.Value())
	case "gte":
		return fmt.Sprintf("%v must be greater than or equal to %s", fe.Field(), fe.Param())
	case "lte":
		return fmt.Sprintf("%v must be less than or equal to %s", fe.Field(), fe.Param())
	case "datetime":
		return fmt.Sprintf("%v must be a valid datetime of format '%v'", fe.Field(), fe.Param())
	case "e164":
		return fmt.Sprintf("%v must be a valid E.164 phone number", fe.Field())
	case "boolean":
		return fmt.Sprintf("%v must be a boolean value", fe.Field())
	case "country":
		return fmt.Sprintf("%v must be a valid country code", fe.Field())
	case "fqdn":
		return fmt.Sprintf("%v must be a valid fully-qualified domain name", fe.Field())
	case "ip":
		return fmt.Sprintf("%v must be a valid IP address", fe.Field())
	case "ipv4":
		return fmt.Sprintf("%v must be a valid IPv4 address", fe.Field())
	case "ipv6":
		return fmt.Sprintf("%v must be a valid IPv6 address", fe.Field())
	case "oneof":
		return fmt.Sprintf("%v must be one of: %v", fe.Field(), fe.Param())
	case "required_with":
		return fmt.Sprintf("%v is required when %v is provided", fe.Field(), fe.Param())
	case "required_without":
		return fmt.Sprintf("%v is required when %v is not provided", fe.Field(), fe.Param())
	case "uuid":
		return fmt.Sprintf("%v must be a valid uuid value", fe.Field())
	case "strong_password":
		return fmt.Sprintf("%s must meet the following criteria: "+
			"at least one lowercase letter, one uppercase letter, one number, one special character,"+
			"and a minimum length of 14 characters", fe.Field())
	case "unique":
		return fmt.Sprintf("%v must have unique values", fe.Field())
	case "excluded_with":
		return fmt.Sprintf("%v must be excluded when %v is provided", fe.Field(), fe.Param())
	case "is_uuid_or_fqdn":
		return fmt.Sprintf("%v must be either valid uuid or valid fqdn", fe.Field())
	case validators.HTTPSURLTag:
		return fmt.Sprintf("%v must be a valid HTTPS url", fe.Field())
	case validators.URLReachableTag:
		return fmt.Sprintf("%v must be reachable", fe.Field())
	}

	return fe.Error()
}

// HandleMessageBusErrorResponse handles ErrorResponse messages for RPC message bus requests
func HandleMessageBusErrorResponse(context *gin.Context, log logger.ILogger, errResponse *tcwire.ErrorResponse) {
	log.Error(
		"error response",
		logger.Fields{
			"errorCode":    errResponse.GetCode(),
			"errorAppCode": errResponse.GetAppCode(),
			"errorMessage": errResponse.GetMessage(),
			"errorDetails": errResponse.GetDetails(),
		},
	)

	switch errResponse.GetAppCode() {
	case tcwire.ErrorResponse_NOT_FOUND:
		NotFoundErrorResponse(errResponse.Message, context)
	case tcwire.ErrorResponse_BAD_REQUEST:
		BadRequestErrorResponse(errResponse.Details, context)
	case tcwire.ErrorResponse_FAILED_PRECONDITION:
		UnprocessableEntityErrorResponse(errResponse.Message, context)
	default:
		InternalServerErrorResponse(errResponse.Message, log, context)
	}
}
