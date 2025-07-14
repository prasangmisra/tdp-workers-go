package models

import (
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/converters"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
	"google.golang.org/protobuf/types/known/anypb"
)

type SubscriptionCreateRequest struct {
	NotificationEmail string                 `json:"notification_email"  binding:"required,email"`
	URL               string                 `json:"url"  binding:"required,url,https_url,url_reachable"`
	Description       *string                `json:"description"`
	Tags              []string               `json:"tags"`
	Metadata          map[string]interface{} `json:"metadata,omitempty"`

	NotificationTypes []string `json:"notification_types" binding:"required,min=1"`
} // @name SubscriptionCreateRequest

type SubscriptionCreateResponse struct {
	*Subscription
	SigningSecret string `json:"signing_secret"`
} // @name SubscriptionCreateResponse

func (s *SubscriptionCreateRequest) ToProto(baseHeader *gcontext.BaseHeader) (*subscription.SubscriptionCreateRequest, error) {
	// If s is nil, return nil to match expected behavior
	if s == nil {
		return nil, nil
	}

	// Convert metadata while preserving nil values
	var metadataProto map[string]*anypb.Any
	if s.Metadata != nil { // Only convert if metadata is non-nil
		var err error
		metadataProto, err = MetadataToProto(s.Metadata)
		if err != nil {
			return nil, err
		}
	}

	// ConvertOrNil ensures a structured transformation
	return converters.ConvertOrNil(s, func(s *SubscriptionCreateRequest) subscription.SubscriptionCreateRequest {
		return subscription.SubscriptionCreateRequest{
			TenantCustomerId:  converters.ConvertOrEmpty(baseHeader, func(h *gcontext.BaseHeader) string { return h.XTenantCustomerID }),
			NotificationEmail: s.NotificationEmail,
			Url:               s.URL,
			Description:       s.Description,
			Tags:              s.Tags,
			Metadata:          metadataProto, // Preserve nil instead of empty map
			NotificationTypes: s.NotificationTypes,
		}
	}), nil
}

func SubscriptionCreateRespFromProto(m *subscription.SubscriptionCreateResponse) *SubscriptionCreateResponse {
	return converters.ConvertOrNil(m, func(m *subscription.SubscriptionCreateResponse) SubscriptionCreateResponse {
		return SubscriptionCreateResponse{
			Subscription:  subscriptionFromProtoHelper(m.GetSubscription()),
			SigningSecret: m.SigningSecret,
		}
	})
}
