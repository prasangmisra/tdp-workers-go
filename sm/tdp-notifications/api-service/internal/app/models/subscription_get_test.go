package models

import (
	"testing"
	"time"

	"github.com/gin-gonic/gin/binding"
	"github.com/google/uuid"
	"github.com/samber/lo"
	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestSubscriptionGetParameterBinding(t *testing.T) {
	t.Parallel()
	validate := binding.Validator
	tests := []struct {
		name         string
		s            SubscriptionGetParameter
		errAssertion require.ErrorAssertionFunc
	}{
		{
			name:         "error - empty ID",
			s:            SubscriptionGetParameter{},
			errAssertion: require.Error,
		},
		{
			name: "error - invalid UUID format",
			s: SubscriptionGetParameter{
				ID: "invalid-uuid",
			},
			errAssertion: require.Error,
		},
		{
			name: "valid UUID format",
			s: SubscriptionGetParameter{
				ID: uuid.New().String(),
			},
			errAssertion: require.NoError,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			tc.errAssertion(t, validate.ValidateStruct(tc.s))
		})
	}
}

func TestSubscriptionFromProto(t *testing.T) {
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
		name     string
		m        *subscription.SubscriptionGetResponse
		expected *SubscriptionGetResponse
	}{
		{
			name: "nil message",
		},
		{
			name: "empty message",
			m:    &subscription.SubscriptionGetResponse{},
			expected: &SubscriptionGetResponse{
				Subscription: nil,
			},
		},
		{
			name: "all fiends are set",
			m: &subscription.SubscriptionGetResponse{
				Subscription: &subscription.SubscriptionDetailsResponse{
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
			expected: &SubscriptionGetResponse{
				Subscription: &Subscription{
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
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			require.Equal(t, tc.expected, SubscriptionGetRespFromProto(tc.m))
		})
	}
}

func TestSubscriptionGetParameter_ToProto(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name       string
		req        *SubscriptionGetParameter
		baseHeader *gcontext.BaseHeader
		expected   *subscription.SubscriptionGetRequest
	}{
		{
			name:     "nil Subscription request",
			req:      nil,
			expected: nil,
		},
		{
			name:     "empty Subscription request",
			req:      &SubscriptionGetParameter{},
			expected: &subscription.SubscriptionGetRequest{},
		},
		{
			name:       "valid Subscription request with baseHeader",
			baseHeader: &gcontext.BaseHeader{XTenantCustomerID: "3e22a1e3-6b8a-4757-8640-f5e5d707109b"},
			req: &SubscriptionGetParameter{
				ID: "1cb6002d-eea0-48b3-87f0-7285536956c9",
			},
			expected: &subscription.SubscriptionGetRequest{
				Id:               "1cb6002d-eea0-48b3-87f0-7285536956c9",
				TenantCustomerId: "3e22a1e3-6b8a-4757-8640-f5e5d707109b",
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
