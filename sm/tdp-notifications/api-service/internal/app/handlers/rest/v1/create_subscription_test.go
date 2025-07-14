package v1_test

import (
	"errors"
	"fmt"
	"net/http"
	"testing"

	"github.com/google/uuid"
	"github.com/lpar/problem"
	"github.com/stretchr/testify/mock"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	tcwire "github.com/tucowsinc/tdp-messages-go/message"
	v1restmock "github.com/tucowsinc/tdp-notifications/api-service/internal/app/mocks/rest/v1"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/app/models"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
	bus "github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/messaging"
)

func TestCreateSubscriptionHandler(t *testing.T) {
	t.Parallel()

	setupValidators(t)

	tests := []struct {
		name       string
		baseHeader *gcontext.BaseHeader
		req        *models.SubscriptionCreateRequest
		mocksF     func(s *v1restmock.IService, req, headers, baseHeader, res any)

		expectedResp   any
		expectedStatus int
	}{
		{
			name:       "happy flow",
			baseHeader: &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			req: &models.SubscriptionCreateRequest{
				URL:               "https://webhook.com",
				NotificationEmail: "notifications@test.com",
				NotificationTypes: []string{"DOMAIN_CREATED"},
			},
			mocksF: func(s *v1restmock.IService, req, headers, baseHeader, res any) {
				s.On("CreateSubscription", mock.Anything, req, headers, baseHeader).
					Return(res, nil).Times(1)
			},

			expectedResp:   &models.SubscriptionCreateResponse{},
			expectedStatus: http.StatusCreated,
		},
		{
			name: "bad request - required header XTenantCustomerID is missing",
			req:  &models.SubscriptionCreateRequest{},
			expectedResp: &problem.ProblemDetails{
				Status: http.StatusBadRequest,
				Title:  "Bad Request",
				Detail: "Header validation error: Key: 'BaseHeader.XTenantCustomerID' Error:Field validation for 'XTenantCustomerID' failed on the 'required' tag",
				Type:   "https://tools.ietf.org/html/rfc7231#section-6.5.1",
			},
			expectedStatus: http.StatusBadRequest,
		},
		{
			name:       "bad request - validation error",
			baseHeader: &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			req:        &models.SubscriptionCreateRequest{URL: "http://webhook.com"},
			expectedResp: &problem.ValidationProblem{
				ProblemDetails: problem.ProblemDetails{
					Status: http.StatusBadRequest,
					Detail: "one or more validation errors occurred while processing the request",
					Type:   "https://tools.ietf.org/html/rfc7231#section-6.5.1",
				},
				ValidationErrors: []problem.ValidationError{
					{
						FieldName: "SubscriptionCreateRequest.NotificationEmail",
						Error:     "NotificationEmail is a required field",
					},
					{
						FieldName: "SubscriptionCreateRequest.URL",
						Error:     "URL must be a valid HTTPS url",
					},
					{
						FieldName: "SubscriptionCreateRequest.NotificationTypes",
						Error:     "NotificationTypes is a required field",
					},
				},
			},
			expectedStatus: http.StatusBadRequest,
		},
		{
			name:       "message bus - timeout error",
			baseHeader: &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			req: &models.SubscriptionCreateRequest{
				URL:               "https://webhook.com",
				NotificationEmail: "notifications@test.com",
				NotificationTypes: []string{"DOMAIN_CREATED"},
			},
			mocksF: func(s *v1restmock.IService, req, headers, baseHeader, res any) {
				s.On("CreateSubscription", mock.Anything, req, headers, baseHeader).
					Return(res, messagebus.ErrCallTimeout).
					Times(1)
			},

			expectedResp: &problem.ProblemDetails{
				Status: http.StatusRequestTimeout,
				Title:  "Request Timeout",
				Detail: "message bus call timeout",
				Type:   "https://tools.ietf.org/html/rfc7231#section-6.5.7",
			},
			expectedStatus: http.StatusRequestTimeout,
		},
		{
			name:       "message bus - timeout error (wrapped)",
			baseHeader: &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			req: &models.SubscriptionCreateRequest{
				URL:               "https://webhook.com",
				NotificationEmail: "notifications@test.com",
				NotificationTypes: []string{"DOMAIN_CREATED"},
			},
			mocksF: func(s *v1restmock.IService, req, headers, baseHeader, res any) {
				s.On("CreateSubscription", mock.Anything, req, headers, baseHeader).
					Return(res, fmt.Errorf("service errror: %w", messagebus.ErrCallTimeout)).
					Times(1)
			},

			expectedResp: &problem.ProblemDetails{
				Status: http.StatusRequestTimeout,
				Title:  "Request Timeout",
				Detail: "message bus call timeout",
				Type:   "https://tools.ietf.org/html/rfc7231#section-6.5.7",
			},
			expectedStatus: http.StatusRequestTimeout,
		},
		{
			name:       "message bus - tcwire ErrorResponse",
			baseHeader: &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			req: &models.SubscriptionCreateRequest{
				URL:               "https://webhook.com",
				NotificationEmail: "notifications@test.com",
				NotificationTypes: []string{"DOMAIN_CREATED"},
			},
			mocksF: func(s *v1restmock.IService, req, headers, baseHeader, res any) {
				s.On("CreateSubscription", mock.Anything, req, headers, baseHeader).
					Return(res, &bus.BusErr{
						ErrorResponse: &tcwire.ErrorResponse{
							Message: "Entity already exists",
							AppCode: tcwire.ErrorResponse_ALREADY_EXISTS,
						}}).Times(1)
			},

			expectedResp: &problem.ProblemDetails{
				Status: http.StatusInternalServerError,
				Title:  "Internal Server Error",
				Detail: "Entity already exists",
				Type:   "https://www.rfc-editor.org/rfc/rfc7231#section-6.6.1",
			},
			expectedStatus: http.StatusInternalServerError,
		},
		{
			name:       "internal server error",
			baseHeader: &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			req: &models.SubscriptionCreateRequest{
				URL:               "https://webhook.com",
				NotificationEmail: "notifications@test.com",
				NotificationTypes: []string{"DOMAIN_CREATED"},
			},
			mocksF: func(s *v1restmock.IService, req, headers, baseHeader, res any) {
				s.On("CreateSubscription", mock.Anything, req, headers, baseHeader).Return(res, errors.New("internal error")).Times(1)
			},

			expectedResp: &problem.ProblemDetails{
				Status: http.StatusInternalServerError,
				Title:  "Internal Server Error",
				Detail: "failed to create subscription",
				Type:   "https://www.rfc-editor.org/rfc/rfc7231#section-6.6.1",
			},
			expectedStatus: http.StatusInternalServerError,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			headers := defaultHeaders(tc.baseHeader)

			serveTestHTTP[models.SubscriptionCreateResponse](t, "POST", "/api/subscriptions",
				func(s *v1restmock.IService, res any) {
					if tc.mocksF != nil {
						tc.mocksF(s, tc.req, headers, tc.baseHeader, res)
					}
				},
				tc.baseHeader, tc.req, tc.expectedResp, tc.expectedStatus)
		})
	}
}
