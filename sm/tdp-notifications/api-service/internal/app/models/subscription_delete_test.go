package models

import (
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
)

func TestSubscriptionsDeleteParameter_ToProto(t *testing.T) {
	t.Parallel()
	subscriptionID := uuid.New().String()

	tests := []struct {
		name       string
		req        *SubscriptionDeleteParameter
		baseHeader *gcontext.BaseHeader
		expected   *subscription.SubscriptionDeleteRequest
	}{
		{
			name:     "nil SubscriptionsGetParameter request",
			req:      nil,
			expected: nil,
		},
		{
			name: "empty SubscriptionsGetParameter request",
			req: &SubscriptionDeleteParameter{
				ID: subscriptionID,
			},
			expected: &subscription.SubscriptionDeleteRequest{
				Id: subscriptionID,
			},
		},
		{
			name:       "valid SubscriptionsGetParameter request with baseHeader",
			baseHeader: &gcontext.BaseHeader{XTenantCustomerID: "3e22a1e3-6b8a-4757-8640-f5e5d707109b"},
			req: &SubscriptionDeleteParameter{
				ID: subscriptionID,
			},
			expected: &subscription.SubscriptionDeleteRequest{
				TenantCustomerId: "3e22a1e3-6b8a-4757-8640-f5e5d707109b",
				Id:               subscriptionID,
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
