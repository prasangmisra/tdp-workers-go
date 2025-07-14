package models

import (
	"net/http"
	"testing"
	"time"

	"github.com/gin-gonic/gin/binding"
	"github.com/google/uuid"
	"github.com/samber/lo"
	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/validators"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestSubscriptionFromProtoUpdate(t *testing.T) {
	t.Parallel()
	// Helper function to convert metadata map to proto safely
	metadataToProtoSafe := func(t *testing.T, metadata map[string]interface{}) map[string]*anypb.Any {
		protoMetadata, err := MetadataToProto(metadata)
		require.NoError(t, err)
		return protoMetadata
	}

	subscriptionID := uuid.New().String()

	metadata := map[string]interface{}{"a": "b"}
	metadataProto := metadataToProtoSafe(t, metadata)
	now := time.Now().UTC()
	yesterday := now.AddDate(0, 0, -1)
	tests := []struct {
		name     string
		m        *subscription.SubscriptionUpdateResponse
		expected *SubscriptionUpdateResponse
	}{
		{
			name: "nil message",
		},
		{
			name: "empty message",
			m:    &subscription.SubscriptionUpdateResponse{},
			expected: &SubscriptionUpdateResponse{
				Subscription: nil},
		},
		{
			name: "all fields are set",
			m: &subscription.SubscriptionUpdateResponse{
				Subscription: &subscription.SubscriptionDetailsResponse{
					Id:                subscriptionID,
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
			expected: &SubscriptionUpdateResponse{
				Subscription: &Subscription{
					ID:                subscriptionID,
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
			require.Equal(t, tc.expected, SubscriptionUpdateRespFromProto(tc.m))
		})
	}
}

func TestSubscriptionUpdateRequestBinding(t *testing.T) {
	t.Parallel()
	validate := binding.Validator
	subscriptionID := uuid.New().String()

	tests := []struct {
		name             string
		s                SubscriptionUpdateRequest
		errAssertion     require.ErrorAssertionFunc
		mockHTTPHeadFunc func(string) (*http.Response, error)
	}{
		{
			name: "valid - empty subscription request",
			s: SubscriptionUpdateRequest{
				ID: subscriptionID,
			},
			errAssertion: require.NoError,
		},
		{
			name: "invalid - empty subscription request with invalid ID",
			s: SubscriptionUpdateRequest{
				ID: "subscriptionID",
			},
			errAssertion: require.Error,
		},
		{
			name: "invalid - subscription request blank ID",
			s: SubscriptionUpdateRequest{
				NotificationEmail: lo.ToPtr("email@gmail.com"),
			},
			errAssertion: require.Error,
		},
		{
			name: "valid - empty NotificationTypes",
			s: SubscriptionUpdateRequest{
				ID:                subscriptionID,
				NotificationEmail: lo.ToPtr("email@gmail.com"),
				NotificationTypes: NotificationTypesUpdate{},
			},
			errAssertion: require.NoError,
		},
		{
			name: "valid - empty add and remove in NotificationTypes",
			s: SubscriptionUpdateRequest{
				ID:                subscriptionID,
				NotificationEmail: lo.ToPtr("email@gmail.com"),
				NotificationTypes: NotificationTypesUpdate{
					Add: []string{},
					Rem: []string{},
				},
			},
			errAssertion: require.NoError,
		},
		{
			name: "valid - common NotificationTypes in 'add' and 'remove'",
			s: SubscriptionUpdateRequest{
				ID:                subscriptionID,
				NotificationEmail: lo.ToPtr("email@gmail.com"),
				NotificationTypes: NotificationTypesUpdate{
					Add: []string{},
					Rem: []string{},
				},
			},
			errAssertion: require.NoError,
		},
		{
			name: "error - NotificationEmail is not valid",
			s: SubscriptionUpdateRequest{
				ID:                subscriptionID,
				NotificationEmail: lo.ToPtr("invalid-email.com"),
				NotificationTypes: NotificationTypesUpdate{
					Add: []string{"DOMAIN_CREATED"},
				},
			},
			errAssertion: require.Error,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			validators.HttpHeadFunc = tc.mockHTTPHeadFunc
			tc.errAssertion(t, validate.ValidateStruct(tc.s))
		})
	}
}

func TestSubscriptionUpdateRequest_ToProto(t *testing.T) {
	t.Parallel()
	// Helper function to convert metadata map to proto safely
	metadataToProtoSafe := func(t *testing.T, metadata map[string]interface{}) map[string]*anypb.Any {
		protoMetadata, err := MetadataToProto(metadata)
		require.NoError(t, err)
		return protoMetadata
	}

	subscriptionID := uuid.New().String()
	tenantCustomerID := uuid.New().String()
	metadata := map[string]interface{}{"a": "b"}
	metadataProto := metadataToProtoSafe(t, metadata)

	tests := []struct {
		name       string
		s          *SubscriptionUpdateRequest
		baseHeader *gcontext.BaseHeader
		expected   *subscription.SubscriptionUpdateRequest
		expectErr  bool
	}{
		{
			name: "nil Subscription request",
		},
		{
			name:     "empty Subscription request",
			s:        &SubscriptionUpdateRequest{},
			expected: &subscription.SubscriptionUpdateRequest{},
		},
		{
			name:       "all fields are set",
			baseHeader: &gcontext.BaseHeader{XTenantCustomerID: tenantCustomerID},
			s: &SubscriptionUpdateRequest{
				ID:                subscriptionID,
				NotificationEmail: lo.ToPtr("email@gmail.com"),
				Description:       lo.ToPtr("Description"),
				Tags:              []string{"a", "b", "c"},
				Metadata:          metadata,
				NotificationTypes: NotificationTypesUpdate{
					Add: []string{"DOMAIN_CREATED", "DOMAIN_RENEWED"},
					Rem: []string{"CONTACT_CREATED", "CONTACT_RENEWED"},
				},
			},
			expected: &subscription.SubscriptionUpdateRequest{
				Id:                   subscriptionID,
				TenantCustomerId:     tenantCustomerID,
				NotificationEmail:    "email@gmail.com",
				Description:          lo.ToPtr("Description"),
				Tags:                 []string{"a", "b", "c"},
				Metadata:             metadataProto,
				AddNotificationTypes: []string{"DOMAIN_CREATED", "DOMAIN_RENEWED"},
				RemNotificationTypes: []string{"CONTACT_CREATED", "CONTACT_RENEWED"},
			},
		},
		{
			name: "MetadataToProto returns an error",
			s: &SubscriptionUpdateRequest{
				Metadata: map[string]interface{}{"invalid": make(chan int)}, // This should cause MetadataToProto to fail.
			},
			expectErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			result, err := tt.s.ToProto(tt.baseHeader)

			if tt.expectErr {
				require.Error(t, err, "expected an error but got none")
			} else {
				require.NoError(t, err, "expected no error but got one")
				require.Equal(t, tt.expected, result)
			}
		})
	}
}
