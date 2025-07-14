package models

import (
	"net/http"
	"testing"
	"time"

	"github.com/gin-gonic/gin/binding"
	"github.com/samber/lo"
	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/config"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/validators"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestSubscriptionFromProtoCreate(t *testing.T) {
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
		m        *subscription.SubscriptionCreateResponse
		expected *SubscriptionCreateResponse
	}{
		{
			name: "nil message",
		},
		{
			name: "empty message",
			m:    &subscription.SubscriptionCreateResponse{},
			expected: &SubscriptionCreateResponse{
				Subscription: nil},
		},
		{
			name: "all fields are set",
			m: &subscription.SubscriptionCreateResponse{
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
				SigningSecret: "secret",
			},
			expected: &SubscriptionCreateResponse{
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
				SigningSecret: "secret",
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			require.Equal(t, tc.expected, SubscriptionCreateRespFromProto(tc.m))
		})
	}
}

func TestSubscriptionCreateRequestBinding(t *testing.T) {
	t.Parallel()
	var cfg config.Config
	cfg.Validator.HttpsUrl = true
	cfg.Validator.UrlReachability = true
	err := validators.RegisterValidators(&cfg) // This registers the https_url validator
	require.NoError(t, err)
	validate := binding.Validator
	tests := []struct {
		name             string
		s                SubscriptionCreateRequest
		errAssertion     require.ErrorAssertionFunc
		mockHTTPHeadFunc func(string) (*http.Response, error)
	}{
		{
			name:         "error - empty subscription request",
			errAssertion: require.Error,
		},
		{
			name: "error - empty NotificationTypes",
			s: SubscriptionCreateRequest{
				NotificationEmail: "email@gmail.com",
				NotificationTypes: []string{},
			},
			errAssertion: require.Error,
		},
		{
			name: "error - invalid NotificationTypes",
			s: SubscriptionCreateRequest{
				NotificationEmail: "email@gmail.com",
				NotificationTypes: []string{"DOMAIN_CREATED", "invalid", "DOMAIN_RENEWED"},
			},
			errAssertion: require.Error,
		},
		{
			name: "error - NotificationEmail is not valid",
			s: SubscriptionCreateRequest{
				NotificationEmail: "invalid",
				NotificationTypes: []string{"DOMAIN_CREATED"},
			},
			errAssertion: require.Error,
		},
		{
			name: "required fields for Webhook channel type",
			s: SubscriptionCreateRequest{
				URL:               "https://webhook.com",
				NotificationEmail: "email@gmail.com",
				NotificationTypes: []string{"DOMAIN_CREATED"},
			},
			errAssertion:     require.NoError,
			mockHTTPHeadFunc: mockHTTPHeadSuccess,
		},
		{
			name: "required fields for Webhook channel type",
			s: SubscriptionCreateRequest{
				URL:               "http://webhook.com",
				NotificationEmail: "email@gmail.com",
				NotificationTypes: []string{"DOMAIN_CREATED"},
			},
			errAssertion:     require.Error,
			mockHTTPHeadFunc: mockHTTPHeadSuccess,
		},
		{
			name: "error - invalid URL",
			s: SubscriptionCreateRequest{
				URL:               "sss",
				NotificationEmail: "email@gmail.com",
				NotificationTypes: []string{"DOMAIN_CREATED"},
			},
			errAssertion:     require.Error,
			mockHTTPHeadFunc: mockHTTPHeadFailure,
		},
		{
			name: "error - URL is missing",
			s: SubscriptionCreateRequest{
				NotificationEmail: "email@gmail.com",
				NotificationTypes: []string{"DOMAIN_CREATED"},
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

func TestSubscriptionCreateRequest_ToProto(t *testing.T) {
	t.Parallel()
	// Helper function to convert metadata map to proto safely
	metadataToProtoSafe := func(t *testing.T, metadata map[string]interface{}) map[string]*anypb.Any {
		protoMetadata, err := MetadataToProto(metadata)
		require.NoError(t, err)
		return protoMetadata
	}

	metadata := map[string]interface{}{"a": "b"}
	metadataProto := metadataToProtoSafe(t, metadata)

	tests := []struct {
		name       string
		s          *SubscriptionCreateRequest
		baseHeader *gcontext.BaseHeader
		expected   *subscription.SubscriptionCreateRequest
		expectErr  bool
	}{
		{
			name: "nil Subscription request",
		},
		{
			name:     "empty Subscription request",
			s:        &SubscriptionCreateRequest{},
			expected: &subscription.SubscriptionCreateRequest{},
		},
		{
			name:       "all fields are set",
			baseHeader: &gcontext.BaseHeader{XTenantCustomerID: "3e22a1e3-6b8a-4757-8640-f5e5d707109b"},
			s: &SubscriptionCreateRequest{
				NotificationEmail: "email@gmail.com",
				URL:               "https://webhook.com",
				Description:       lo.ToPtr("Description"),
				Tags:              []string{"a", "b", "c"},
				Metadata:          metadata,
				NotificationTypes: []string{"DOMAIN_CREATED", "DOMAIN_RENEWED"},
			},
			expected: &subscription.SubscriptionCreateRequest{
				TenantCustomerId:  "3e22a1e3-6b8a-4757-8640-f5e5d707109b",
				NotificationEmail: "email@gmail.com",
				Url:               "https://webhook.com",
				Description:       lo.ToPtr("Description"),
				Tags:              []string{"a", "b", "c"},
				Metadata:          metadataProto,
				NotificationTypes: []string{"DOMAIN_CREATED", "DOMAIN_RENEWED"},
			},
		},
		{
			name: "MetadataToProto returns an error",
			s: &SubscriptionCreateRequest{
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
