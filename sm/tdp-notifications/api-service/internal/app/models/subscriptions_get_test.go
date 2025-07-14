package models

import (
	"testing"
	"time"

	"github.com/samber/lo"
	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestSubscriptionsGetParameter_ToProto(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name       string
		req        *SubscriptionsGetParameter
		baseHeader *gcontext.BaseHeader
		expected   *subscription.SubscriptionListRequest
	}{
		{
			name:     "nil SubscriptionsGetParameter request",
			req:      nil,
			expected: nil,
		},
		{
			name: "empty SubscriptionsGetParameter request",
			req:  &SubscriptionsGetParameter{},
			expected: &subscription.SubscriptionListRequest{
				Pagination: &common.PaginationRequest{
					PageSize:      0,
					PageNumber:    0,
					SortBy:        "",
					SortDirection: "",
				},
				TenantCustomerId: "",
			},
		},
		{
			name:       "valid SubscriptionsGetParameter request with baseHeader",
			baseHeader: &gcontext.BaseHeader{XTenantCustomerID: "3e22a1e3-6b8a-4757-8640-f5e5d707109b"},
			req: &SubscriptionsGetParameter{
				Pagination: Pagination{
					PageSize:      10,
					PageNumber:    1,
					SortBy:        "created_date",
					SortDirection: "asc",
				},
			},
			expected: &subscription.SubscriptionListRequest{
				TenantCustomerId: "3e22a1e3-6b8a-4757-8640-f5e5d707109b",
				Pagination: &common.PaginationRequest{
					PageSize:      10,
					PageNumber:    1,
					SortBy:        "created_date",
					SortDirection: "asc",
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			require.Equal(t, tt.expected, tt.req.ToProto(tt.baseHeader))
		})
	}
}

func TestSubscriptionsGetRespFromProto(t *testing.T) {
	t.Parallel()
	// Helper function to convert metadata map to proto safely
	metadataToProtoSafe := func(t *testing.T, metadata map[string]interface{}) map[string]*anypb.Any {
		protoMetadata, err := MetadataToProto(metadata)
		require.NoError(t, err)
		return protoMetadata
	}

	metadata := map[string]interface{}{"a": "b"}
	metadataProto := metadataToProtoSafe(t, metadata)
	now := time.Now().UTC()
	yesterday := now.AddDate(0, 0, -1)

	tests := []struct {
		name       string
		m          *subscription.SubscriptionListResponse
		pagination *Pagination
		totalCount int
		expected   *SubscriptionsGetResponse
	}{
		{
			name: "nil message",
		},
		{
			name:       "empty message",
			m:          &subscription.SubscriptionListResponse{},
			pagination: &Pagination{PageSize: 10, PageNumber: 1},
			totalCount: 0,
			expected: &SubscriptionsGetResponse{
				Items: []*Subscription{},
				PagedViewModel: PagedViewModel{
					PageSize:        10,
					PageNumber:      1,
					TotalCount:      0,
					TotalPages:      0,
					HasNextPage:     false,
					HasPreviousPage: false,
				},
			},
		},
		{
			name: "all fields are set",
			m: &subscription.SubscriptionListResponse{
				Subscriptions: []*subscription.SubscriptionDetailsResponse{
					{
						Id:                "1cb6002d-eea0-48b3-87f0-7285536956c9",
						NotificationEmail: "email@gmail.com",
						Url:               "https://webhook.com",
						Description:       lo.ToPtr("Description"),
						Tags:              []string{"a", "b", "c"},
						Metadata:          metadataProto,
						Status:            subscription.SubscriptionStatus_ACTIVE,
						NotificationTypes: []string{"DOMAIN_CREATED", "DOMAIN_RENEWED"},
						CreatedDate:       timestamppb.New(yesterday),
						UpdatedDate:       timestamppb.New(now),
					},
				},
				TotalCount: 1,
			},
			pagination: &Pagination{PageSize: 10, PageNumber: 1},
			totalCount: 1,
			expected: &SubscriptionsGetResponse{
				Items: []*Subscription{
					{
						ID:                "1cb6002d-eea0-48b3-87f0-7285536956c9",
						NotificationEmail: "email@gmail.com",
						URL:               "https://webhook.com",
						Description:       lo.ToPtr("Description"),
						Tags:              []string{"a", "b", "c"},
						Metadata:          metadata,
						Status:            Active,
						NotificationTypes: []string{"DOMAIN_CREATED", "DOMAIN_RENEWED"},
						CreatedDate:       &yesterday,
						UpdatedDate:       &now,
					},
				},
				PagedViewModel: PagedViewModel{
					PageSize:        10,
					PageNumber:      1,
					TotalCount:      1,
					TotalPages:      1,
					HasNextPage:     false,
					HasPreviousPage: false,
				},
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			require.Equal(t, tc.expected, SubscriptionsGetRespFromProto(tc.m, tc.pagination, tc.totalCount))
		})
	}
}
