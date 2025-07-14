package v1_test

import (
	"errors"
	"fmt"
	"net/http"
	"testing"

	"github.com/google/uuid"
	"github.com/jinzhu/copier"
	"github.com/lpar/problem"
	"github.com/samber/lo"
	"github.com/stretchr/testify/mock"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	tcwire "github.com/tucowsinc/tdp-messages-go/message"
	v1restmock "github.com/tucowsinc/tdp-notifications/api-service/internal/app/mocks/rest/v1"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/app/models"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
	bus "github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/messaging"
)

func TestUpdateSubscriptionHandler(t *testing.T) {
	t.Parallel()

	setupValidators(t)
	notificationEmail := "notifications@test.com"
	subscriptionID := uuid.New().String()

	tests := []struct {
		name           string
		baseHeader     *gcontext.BaseHeader
		subscriptionID string
		req            *models.SubscriptionUpdateRequest
		mocksF         func(s *v1restmock.IService, req, headers, baseHeader, res any)

		expectedResp   any
		expectedStatus int
	}{
		{
			name:           "happy flow",
			baseHeader:     &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			subscriptionID: subscriptionID,
			req: &models.SubscriptionUpdateRequest{
				NotificationEmail: lo.ToPtr(notificationEmail),
				NotificationTypes: models.NotificationTypesUpdate{
					Add: []string{"DOMAIN_CREATED"},
					Rem: []string{"DOMAIN_DELETED"},
				},
			},
			mocksF: func(s *v1restmock.IService, req, headers, baseHeader, res any) {
				s.On("UpdateSubscription", mock.Anything, req, headers, baseHeader).
					Return(res, nil).Times(1)
			},

			expectedResp: &models.SubscriptionUpdateResponse{
				Subscription: &models.Subscription{
					ID: subscriptionID,
				},
			},
			expectedStatus: http.StatusOK,
		},
		{
			name:           "bad request - required header XTenantCustomerID is missing",
			subscriptionID: subscriptionID,
			req:            &models.SubscriptionUpdateRequest{},
			expectedResp: &problem.ProblemDetails{
				Status: http.StatusBadRequest,
				Title:  "Bad Request",
				Detail: "Header validation error: Key: 'BaseHeader.XTenantCustomerID' Error:Field validation for 'XTenantCustomerID' failed on the 'required' tag",
				Type:   "https://tools.ietf.org/html/rfc7231#section-6.5.1",
			},
			expectedStatus: http.StatusBadRequest,
		},
		{
			name:           "bad request - invalid ID",
			baseHeader:     &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			subscriptionID: "invalid-id",
			req:            &models.SubscriptionUpdateRequest{},
			expectedResp: &problem.ValidationProblem{
				ProblemDetails: problem.ProblemDetails{
					Status: http.StatusBadRequest,
					Detail: "one or more validation errors occurred while processing the request",
					Type:   "https://tools.ietf.org/html/rfc7231#section-6.5.1",
				},
				ValidationErrors: []problem.ValidationError{
					{
						FieldName: "SubscriptionUpdateRequest.ID",
						Error:     "ID must be a valid uuid value",
					},
				},
			},
			expectedStatus: http.StatusBadRequest,
		},
		{
			name:           "bad request - blank ID",
			baseHeader:     &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			subscriptionID: "",
			req:            &models.SubscriptionUpdateRequest{},
			expectedStatus: http.StatusNotFound,
		},
		{
			name:           "bad request - validation error",
			baseHeader:     &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			subscriptionID: subscriptionID,
			req: &models.SubscriptionUpdateRequest{
				NotificationEmail: lo.ToPtr("something.com"),
			},
			expectedResp: &problem.ValidationProblem{
				ProblemDetails: problem.ProblemDetails{
					Status: http.StatusBadRequest,
					Detail: "one or more validation errors occurred while processing the request",
					Type:   "https://tools.ietf.org/html/rfc7231#section-6.5.1",
				},
				ValidationErrors: []problem.ValidationError{
					{
						FieldName: "SubscriptionUpdateRequest.NotificationEmail",
						Error:     "something.com is not a valid email",
					},
				},
			},
			expectedStatus: http.StatusBadRequest,
		},
		{
			name:           "message bus - timeout error",
			subscriptionID: subscriptionID,
			baseHeader:     &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			req: &models.SubscriptionUpdateRequest{
				NotificationEmail: lo.ToPtr(notificationEmail),
				NotificationTypes: models.NotificationTypesUpdate{
					Add: []string{"DOMAIN_CREATED"},
					Rem: []string{"DOMAIN_DELETED"},
				},
			},
			mocksF: func(s *v1restmock.IService, req, headers, baseHeader, res any) {
				s.On("UpdateSubscription", mock.Anything, req, headers, baseHeader).
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
			name:           "message bus - timeout error (wrapped)",
			baseHeader:     &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			subscriptionID: subscriptionID,
			req: &models.SubscriptionUpdateRequest{
				NotificationEmail: lo.ToPtr(notificationEmail),
				NotificationTypes: models.NotificationTypesUpdate{
					Add: []string{"DOMAIN_CREATED"},
					Rem: []string{"DOMAIN_DELETED"},
				},
			},
			mocksF: func(s *v1restmock.IService, req, headers, baseHeader, res any) {
				s.On("UpdateSubscription", mock.Anything, req, headers, baseHeader).
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
			name:           "message bus - tcwire ErrorResponse - not found",
			baseHeader:     &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			subscriptionID: subscriptionID,
			req: &models.SubscriptionUpdateRequest{
				NotificationEmail: lo.ToPtr(notificationEmail),
				NotificationTypes: models.NotificationTypesUpdate{
					Add: []string{"DOMAIN_CREATED"},
					Rem: []string{"DOMAIN_DELETED"},
				},
			},
			mocksF: func(s *v1restmock.IService, req, headers, baseHeader, res any) {
				s.On("UpdateSubscription", mock.Anything, req, headers, baseHeader).
					Return(res, &bus.BusErr{
						ErrorResponse: &tcwire.ErrorResponse{
							Message: "not found",
							AppCode: tcwire.ErrorResponse_NOT_FOUND,
						}}).Times(1)
			},

			expectedResp: &problem.ProblemDetails{
				Status: http.StatusNotFound,
				Title:  "Not Found",
				Detail: "not found",
				Type:   "https://tools.ietf.org/html/rfc7231#section-6.5.4",
			},
			expectedStatus: http.StatusNotFound,
		},
		{
			name:           "message bus - tcwire ErrorResponse",
			baseHeader:     &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			subscriptionID: subscriptionID,
			req: &models.SubscriptionUpdateRequest{
				NotificationEmail: lo.ToPtr(notificationEmail),
				NotificationTypes: models.NotificationTypesUpdate{
					Add: []string{"DOMAIN_CREATED"},
					Rem: []string{"DOMAIN_DELETED"},
				},
			},
			mocksF: func(s *v1restmock.IService, req, headers, baseHeader, res any) {
				s.On("UpdateSubscription", mock.Anything, req, headers, baseHeader).
					Return(res, &bus.BusErr{
						ErrorResponse: &tcwire.ErrorResponse{
							Message: "Invalid Notification Type",
							AppCode: tcwire.ErrorResponse_FAILED_OPERATION,
						}}).Times(1)
			},

			expectedResp: &problem.ProblemDetails{
				Status: http.StatusInternalServerError,
				Title:  "Internal Server Error",
				Detail: "Invalid Notification Type",
				Type:   "https://www.rfc-editor.org/rfc/rfc7231#section-6.6.1",
			},
			expectedStatus: http.StatusInternalServerError,
		},
		{
			name:           "internal server error",
			baseHeader:     &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			subscriptionID: subscriptionID,
			req: &models.SubscriptionUpdateRequest{
				NotificationEmail: lo.ToPtr(notificationEmail),
				NotificationTypes: models.NotificationTypesUpdate{
					Add: []string{"DOMAIN_CREATED"},
					Rem: []string{"DOMAIN_CREATED"},
				},
			},
			mocksF: func(s *v1restmock.IService, req, headers, baseHeader, res any) {
				s.On("UpdateSubscription", mock.Anything, req, headers, baseHeader).Return(res, errors.New("internal error")).Times(1)
			},

			expectedResp: &problem.ProblemDetails{
				Status: http.StatusInternalServerError,
				Title:  "Internal Server Error",
				Detail: "failed to update subscription",
				Type:   "https://www.rfc-editor.org/rfc/rfc7231#section-6.6.1",
			},
			expectedStatus: http.StatusInternalServerError,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			headers := defaultHeaders(tc.baseHeader)

			serveTestHTTP[models.SubscriptionUpdateResponse](t, "PATCH", "/api/subscriptions/"+tc.subscriptionID,
				func(s *v1restmock.IService, res any) {
					if tc.mocksF != nil {
						dupRec := models.SubscriptionUpdateRequest{}
						copier.Copy(&dupRec, tc.req)
						dupRec.ID = tc.subscriptionID
						tc.mocksF(s, &dupRec, headers, tc.baseHeader, res)
					}
				},
				tc.baseHeader, tc.req, tc.expectedResp, tc.expectedStatus)
		})
	}
}
