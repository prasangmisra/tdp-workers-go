package models

import (
	"github.com/samber/lo"
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/converters"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
)

type NotificationTypesUpdate struct {
	Add []string `json:"add" binding:"required"`
	Rem []string `json:"rem" binding:"required"`
}

type SubscriptionUpdateRequest struct {
	ID                string                 `uri:"id" json:"-" binding:"required,uuid"`
	NotificationEmail *string                `json:"notification_email" binding:"omitempty,email"`
	Description       *string                `json:"description" binding:"omitempty"`
	Tags              []string               `json:"tags" binding:"omitempty"`
	Metadata          map[string]interface{} `json:"metadata" binding:"omitempty"`

	NotificationTypes NotificationTypesUpdate `json:"notification_types" binding:"omitempty"`
} // @name SubscriptionUpdateRequest

type SubscriptionUpdateResponse struct {
	*Subscription
} // @name SubscriptionUpdateResponse

func (s *SubscriptionUpdateRequest) ToProto(baseHeader *gcontext.BaseHeader) (*subscription.SubscriptionUpdateRequest, error) {
	// If s is nil, return nil to match expected behavior
	if s == nil {
		return nil, nil
	}

	// Convert metadata while preserving nil values
	metadataProto, err := MetadataToProto(s.Metadata)
	if err != nil {
		return nil, err
	}

	// ConvertOrNil ensures a structured transformation
	return converters.ConvertOrNil(s, func(s *SubscriptionUpdateRequest) subscription.SubscriptionUpdateRequest {
		return subscription.SubscriptionUpdateRequest{
			Id:                   s.ID,
			TenantCustomerId:     converters.ConvertOrEmpty(baseHeader, func(h *gcontext.BaseHeader) string { return h.XTenantCustomerID }),
			Description:          s.Description,
			NotificationEmail:    lo.FromPtr(s.NotificationEmail),
			Tags:                 s.Tags,
			Metadata:             metadataProto, // Preserve nil instead of empty map
			AddNotificationTypes: s.NotificationTypes.Add,
			RemNotificationTypes: s.NotificationTypes.Rem,
		}
	}), nil
}

func SubscriptionUpdateRespFromProto(m *subscription.SubscriptionUpdateResponse) *SubscriptionUpdateResponse {
	return converters.ConvertOrNil(m, func(m *subscription.SubscriptionUpdateResponse) SubscriptionUpdateResponse {
		return SubscriptionUpdateResponse{
			Subscription: subscriptionFromProtoHelper(m.GetSubscription()),
		}
	})
}
