package v1_test

import (
	"errors"
	"net/http"
	"testing"

	"github.com/google/uuid"
	"github.com/lpar/problem"
	"github.com/stretchr/testify/mock"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	v1restmock "github.com/tucowsinc/tdp-notifications/api-service/internal/app/mocks/rest/v1"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/app/models"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
)

func TestGetSubscriptionsHandler(t *testing.T) {
	t.Parallel()
	setupValidators(t)

	tests := []struct {
		name           string
		baseHeader     *gcontext.BaseHeader
		queryParams    map[string]string
		mocksF         func(s *v1restmock.IService, headers map[string]any, baseHeader *gcontext.BaseHeader, res any)
		expectedResp   any
		expectedStatus int
	}{
		{
			name:       "happy flow",
			baseHeader: &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			queryParams: map[string]string{
				"page_size":      "10",
				"page_number":    "1",
				"sort_by":        "created_date",
				"sort_direction": "desc",
			},
			mocksF: func(s *v1restmock.IService, headers map[string]any, baseHeader *gcontext.BaseHeader, res any) {
				req := &models.SubscriptionsGetParameter{
					Pagination: models.Pagination{
						PageSize:      10,
						PageNumber:    1,
						SortBy:        "created_date",
						SortDirection: "desc",
					},
				}
				s.On("GetSubscriptions", mock.Anything, req, headers, baseHeader).
					Return(res, nil).Times(1)
			},
			expectedResp: &models.SubscriptionsGetResponse{
				Items: []*models.Subscription{
					{
						ID:                "subscription_id_1",
						URL:               "https://webhook1.com",
						NotificationTypes: []string{"DOMAIN_CREATED"},
						Status:            models.Active,
					},
					{
						ID:                "subscription_id_2",
						URL:               "https://webhook2.com",
						NotificationTypes: []string{"DOMAIN_CREATED"},
						Status:            models.Active,
					},
				},
				PagedViewModel: models.PagedViewModel{
					PageSize:        10,
					PageNumber:      1,
					TotalCount:      2,
					TotalPages:      1,
					HasNextPage:     false,
					HasPreviousPage: false,
				},
			},
			expectedStatus: http.StatusOK,
		},
		{
			name:       "happy flow - no query params (default values)",
			baseHeader: &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			mocksF: func(s *v1restmock.IService, headers map[string]any, baseHeader *gcontext.BaseHeader, res any) {
				req := &models.SubscriptionsGetParameter{
					Pagination: models.Pagination{
						PageSize:      10,
						PageNumber:    1,
						SortBy:        "created_date",
						SortDirection: "asc",
					},
				}
				s.On("GetSubscriptions", mock.Anything, req, headers, baseHeader).
					Return(res, nil).Times(1)
			},
			expectedResp: &models.SubscriptionsGetResponse{
				Items: []*models.Subscription{
					{
						ID:                "subscription_id_1",
						URL:               "https://webhook1.com",
						NotificationTypes: []string{"DOMAIN_CREATED"},
						Status:            models.Active,
					},
					{
						ID:                "subscription_id_2",
						URL:               "https://webhook2.com",
						NotificationTypes: []string{"CONTACT_CREATED"},
						Status:            models.Active,
					},
				},
				PagedViewModel: models.PagedViewModel{
					PageSize:        10,
					PageNumber:      1,
					TotalCount:      2,
					TotalPages:      1,
					HasNextPage:     false,
					HasPreviousPage: false,
				},
			},
			expectedStatus: http.StatusOK,
		},
		{
			name:        "bad request - missing XTenantCustomerID header",
			queryParams: map[string]string{},
			expectedResp: &problem.ProblemDetails{
				Status: http.StatusBadRequest,
				Title:  "Bad Request",
				Detail: "Header validation error: Key: 'BaseHeader.XTenantCustomerID' Error:Field validation for 'XTenantCustomerID' failed on the 'required' tag",
				Type:   "https://tools.ietf.org/html/rfc7231#section-6.5.1",
			},
			expectedStatus: http.StatusBadRequest,
		},
		{
			name:       "validation error - invalid pagination",
			baseHeader: &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			queryParams: map[string]string{
				"page_size":   "-11",
				"page_number": "10",
			},
			expectedResp: &problem.ProblemDetails{
				Status:   http.StatusBadRequest,
				Title:    "",
				Detail:   "Key: 'SubscriptionsGetParameter.Pagination.PageSize' Error:Field validation for 'PageSize' failed on the 'gte' tag",
				Type:     "https://tools.ietf.org/html/rfc7231#section-6.5.1",
				Instance: "",
			},
			expectedStatus: http.StatusBadRequest,
		},
		{
			name:       "message bus - timeout error",
			baseHeader: &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			queryParams: map[string]string{
				"page_size":      "10",
				"page_number":    "1",
				"sort_direction": "asc",
			},
			mocksF: func(s *v1restmock.IService, headers map[string]any, baseHeader *gcontext.BaseHeader, res any) {
				s.On("GetSubscriptions", mock.Anything, mock.Anything, headers, baseHeader).
					Return(res, messagebus.ErrCallTimeout).Times(1)
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
			name:       "message bus - internal error",
			baseHeader: &gcontext.BaseHeader{XTenantCustomerID: uuid.New().String()},
			queryParams: map[string]string{
				"page_size":      "10",
				"page_number":    "1",
				"sort_direction": "asc",
			},
			mocksF: func(s *v1restmock.IService, headers map[string]any, baseHeader *gcontext.BaseHeader, res any) {
				s.On("GetSubscriptions", mock.Anything, mock.Anything, headers, baseHeader).
					Return(res, errors.New("internal error")).
					Times(1)
			},
			expectedResp: &problem.ProblemDetails{
				Status: http.StatusInternalServerError,
				Title:  "Internal Server Error",
				Detail: "failed to get subscriptions",
				Type:   "https://www.rfc-editor.org/rfc/rfc7231#section-6.6.1",
			},
			expectedStatus: http.StatusInternalServerError,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			urlPath := buildURLWithQuery(t, "/api/subscriptions", tc.queryParams)
			headers := defaultHeaders(tc.baseHeader)

			serveTestHTTP[models.SubscriptionsGetResponse](t, "GET", urlPath,
				func(s *v1restmock.IService, res any) {
					if tc.mocksF != nil {
						tc.mocksF(s, headers, tc.baseHeader, res)
					}
				},
				tc.baseHeader, nil, tc.expectedResp, tc.expectedStatus)
		})
	}
}
