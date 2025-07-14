package v1_test

import (
	"errors"
	"fmt"
	"net/http"
	"testing"
	"time"

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

// TestResumeSubscriptionHandler tests the ResumeSubscriptionHandler function
func TestResumeSubscriptionHandler(t *testing.T) {
	t.Parallel()

	subscriptionID := uuid.New().String()
	now := time.Now().UTC()

	tests := []struct {
		name           string
		baseHeader     *gcontext.BaseHeader
		subscriptionID string
		mocksF         func(s *v1restmock.IService, req string, headers, baseHeader, res any)
		expectedResp   any
		expectedStatus int
	}{
		{
			name:           "Subscription resumed successfully",
			baseHeader:     &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			subscriptionID: subscriptionID,
			mocksF: func(s *v1restmock.IService, subscriptionID string, headers, baseHeader, res any) {
				req := &models.SubscriptionResumeParameter{ID: subscriptionID}
				s.On("ResumeSubscription", mock.Anything, req, headers, baseHeader).Return(res, nil).Times(1)
			},
			expectedResp: &models.SubscriptionResumeResponse{
				Subscription: &models.Subscription{
					ID:                subscriptionID,
					NotificationEmail: "notifications@test.com",
					URL:               "https://webhook.com",
					Status:            models.Active,
					Tags:              []string{"tag1", "tag2"},
					Metadata:          map[string]interface{}{"key1": "value1"},
					NotificationTypes: []string{"DOMAIN_CREATED"},
					CreatedDate:       &now,
					UpdatedDate:       &now,
				},
			},
			expectedStatus: http.StatusOK,
		},
		{
			name:           "subscription not found",
			baseHeader:     &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			subscriptionID: subscriptionID,
			mocksF: func(s *v1restmock.IService, subscriptionID string, headers, baseHeader, res any) {
				req := &models.SubscriptionResumeParameter{ID: subscriptionID}
				s.On("ResumeSubscription", mock.Anything, req, headers, baseHeader).
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
			name:           "validation error - invalid UUID",
			baseHeader:     &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			subscriptionID: "invalid-uuid",
			expectedResp: &problem.ValidationProblem{
				ProblemDetails: problem.ProblemDetails{
					Status: http.StatusBadRequest,
					Detail: "one or more validation errors occurred while processing the request",
					Type:   "https://tools.ietf.org/html/rfc7231#section-6.5.1",
				},
				ValidationErrors: []problem.ValidationError{
					{
						FieldName: "SubscriptionResumeParameter.ID",
						Error:     "ID must be a valid uuid value",
					},
				},
			},
			expectedStatus: http.StatusBadRequest,
		},
		{
			name:           "precondition error - Subscription is not Paused",
			baseHeader:     &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			subscriptionID: subscriptionID,
			mocksF: func(s *v1restmock.IService, subscriptionID string, headers, baseHeader, res any) {
				req := &models.SubscriptionResumeParameter{ID: subscriptionID}
				s.On("ResumeSubscription", mock.Anything, req, headers, baseHeader).
					Return(nil, &bus.BusErr{
						ErrorResponse: &tcwire.ErrorResponse{
							Message: "Subscription not paused",
							AppCode: tcwire.ErrorResponse_FAILED_PRECONDITION,
						}}).Times(1)
			},
			expectedResp: &problem.ProblemDetails{
				Status: http.StatusUnprocessableEntity,
				Title:  "Unprocessable Entity",
				Detail: "Subscription not paused",
				Type:   "https://www.rfc-editor.org/rfc/rfc4918#section-11.2",
			},
			expectedStatus: http.StatusUnprocessableEntity,
		},
		{
			name:           "message bus timeout",
			baseHeader:     &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			subscriptionID: subscriptionID,
			mocksF: func(s *v1restmock.IService, subscriptionID string, headers, baseHeader, res any) {
				req := &models.SubscriptionResumeParameter{ID: subscriptionID}
				s.On("ResumeSubscription", mock.Anything, req, headers, baseHeader).
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
			mocksF: func(s *v1restmock.IService, subscriptionID string, headers, baseHeader, res any) {
				req := &models.SubscriptionResumeParameter{ID: subscriptionID}
				s.On("ResumeSubscription", mock.Anything, req, headers, baseHeader).
					Return(nil, errors.New("internal error")).Times(1)
			},
			expectedResp: &problem.ProblemDetails{
				Status: http.StatusInternalServerError,
				Title:  "Internal Server Error",
				Detail: "failed to resume subscription",
				Type:   "https://www.rfc-editor.org/rfc/rfc7231#section-6.6.1",
			},
			expectedStatus: http.StatusInternalServerError,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			headers := defaultHeaders(tc.baseHeader)

			serveTestHTTP[models.SubscriptionResumeResponse](t, "PATCH", fmt.Sprintf("/api/subscriptions/%s/resume", tc.subscriptionID),
				func(s *v1restmock.IService, res any) {
					if tc.mocksF != nil {
						tc.mocksF(s, tc.subscriptionID, headers, tc.baseHeader, res)
					}
				},
				tc.baseHeader, tc.subscriptionID, tc.expectedResp, tc.expectedStatus)
		})
	}
}
