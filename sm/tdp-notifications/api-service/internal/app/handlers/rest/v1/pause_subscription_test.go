package v1_test

import (
	"errors"
	"fmt"
	"net/http"
	"testing"
	"time"

	tcwire "github.com/tucowsinc/tdp-messages-go/message"
	bus "github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/messaging"

	"github.com/google/uuid"
	"github.com/lpar/problem"
	"github.com/stretchr/testify/mock"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	v1restmock "github.com/tucowsinc/tdp-notifications/api-service/internal/app/mocks/rest/v1"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/app/models"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
)

// TestPauseSubscriptionHandler tests the PauseSubscriptionHandler
func TestPauseSubscriptionHandler(t *testing.T) {
	t.Parallel()

	subscriptionID := uuid.New().String()
	now := time.Now().UTC()

	tests := []struct {
		name           string
		baseHeader     *gcontext.BaseHeader
		subscriptionID string
		req            *models.SubscriptionPauseParameter
		mocksF         func(s *v1restmock.IService, subscriptionID string, req, headers, baseHeader, res any)
		expectedResp   any
		expectedStatus int
	}{
		{
			name:           "validation error - invalid UUID",
			baseHeader:     &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			subscriptionID: "invalid-uuid",
			req: &models.SubscriptionPauseParameter{
				ID: "invalid-uuid",
			},
			expectedResp: &problem.ValidationProblem{
				ProblemDetails: problem.ProblemDetails{
					Status: http.StatusBadRequest,
					Detail: "one or more validation errors occurred while processing the request",
					Type:   "https://tools.ietf.org/html/rfc7231#section-6.5.1",
				},
				ValidationErrors: []problem.ValidationError{
					{
						FieldName: "SubscriptionPauseParameter.ID",
						Error:     "ID must be a valid uuid value",
					},
				},
			},
			expectedStatus: http.StatusBadRequest,
		},
		{
			name:           "subscription not found",
			baseHeader:     &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			subscriptionID: subscriptionID,
			req: &models.SubscriptionPauseParameter{
				ID: subscriptionID,
			},
			mocksF: func(s *v1restmock.IService, subscriptionID string, req, headers, baseHeader, res any) {
				s.On("PauseSubscription", mock.Anything, req, headers, baseHeader).
					Return(nil, &bus.BusErr{
						ErrorResponse: &tcwire.ErrorResponse{
							Message: "Subscription not found",
							AppCode: tcwire.ErrorResponse_NOT_FOUND,
						}}).Times(1)
			},
			expectedResp: &problem.ProblemDetails{
				Status: http.StatusNotFound,
				Title:  "Not Found",
				Detail: "Subscription not found",
				Type:   "https://tools.ietf.org/html/rfc7231#section-6.5.4",
			},
			expectedStatus: http.StatusNotFound,
		},
		{
			name:           "message bus timeout",
			baseHeader:     &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			subscriptionID: subscriptionID,
			req: &models.SubscriptionPauseParameter{
				ID: subscriptionID,
			},
			mocksF: func(s *v1restmock.IService, subscriptionID string, req, headers, baseHeader, res any) {
				s.On("PauseSubscription", mock.Anything, req, headers, baseHeader).
					Return(nil, messagebus.ErrCallTimeout).Times(1)
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
			name:           "internal server error",
			baseHeader:     &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			subscriptionID: subscriptionID,
			req: &models.SubscriptionPauseParameter{
				ID: subscriptionID,
			},
			mocksF: func(s *v1restmock.IService, subscriptionID string, req, headers, baseHeader, res any) {
				s.On("PauseSubscription", mock.Anything, req, headers, baseHeader).
					Return(nil, errors.New("internal error")).Times(1)
			},
			expectedResp: &problem.ProblemDetails{
				Status: http.StatusInternalServerError,
				Title:  "Internal Server Error",
				Detail: "failed to pause subscription",
				Type:   "https://www.rfc-editor.org/rfc/rfc7231#section-6.6.1",
			},
			expectedStatus: http.StatusInternalServerError,
		},
		{
			name:           "unprocessable entity - failed precondition",
			baseHeader:     &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			subscriptionID: subscriptionID,
			req: &models.SubscriptionPauseParameter{
				ID: subscriptionID,
			},
			mocksF: func(s *v1restmock.IService, subscriptionID string, req, headers, baseHeader, res any) {
				s.On("PauseSubscription", mock.Anything, req, headers, baseHeader).
					Return(nil, &bus.BusErr{
						ErrorResponse: &tcwire.ErrorResponse{
							Message: "Subscription is not in a valid state to be paused",
							AppCode: tcwire.ErrorResponse_FAILED_PRECONDITION,
						},
					}).Times(1)
			},
			expectedResp: &problem.ProblemDetails{
				Status: http.StatusUnprocessableEntity,
				Title:  "Unprocessable Entity",
				Detail: "Subscription is not in a valid state to be paused",
				Type:   "https://www.rfc-editor.org/rfc/rfc4918#section-11.2",
			},
			expectedStatus: http.StatusUnprocessableEntity,
		},
		{
			name:           "successful pause",
			baseHeader:     &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			subscriptionID: subscriptionID,
			req: &models.SubscriptionPauseParameter{
				ID: subscriptionID,
			},
			mocksF: func(s *v1restmock.IService, subscriptionID string, req, headers, baseHeader, res any) {
				s.On("PauseSubscription", mock.Anything, req, headers, baseHeader).
					Return(res, nil).Times(1)
			},
			expectedResp: &models.SubscriptionPauseResponse{
				Subscription: &models.Subscription{
					ID:                subscriptionID,
					NotificationEmail: "notifications@test.com",
					URL:               "https://webhook.com",
					Status:            models.Paused,
					Tags:              []string{"tag1", "tag2"},
					Metadata:          map[string]interface{}{"key1": "value1"},
					NotificationTypes: []string{"DOMAIN_CREATED"},
					CreatedDate:       &now,
					UpdatedDate:       &now,
				},
			},
			expectedStatus: http.StatusOK,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			headers := defaultHeaders(tc.baseHeader)

			serveTestHTTP[models.SubscriptionPauseResponse](t, http.MethodPatch, fmt.Sprintf("/api/subscriptions/%s/pause", tc.subscriptionID),
				func(s *v1restmock.IService, res any) {
					if tc.mocksF != nil {
						tc.mocksF(s, tc.subscriptionID, tc.req, headers, tc.baseHeader, res)
					}
				},
				tc.baseHeader, tc.req, tc.expectedResp, tc.expectedStatus)
		})
	}
}
