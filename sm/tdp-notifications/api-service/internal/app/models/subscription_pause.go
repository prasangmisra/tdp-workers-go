package models

import (
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/converters"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
)

type SubscriptionPauseParameter struct {
	ID string `uri:"id" binding:"required,uuid"`
} // @name SubscriptionPauseRequest

type SubscriptionPauseResponse struct {
	*Subscription
} // @name SubscriptionPauseResponse

func SubscriptionPauseRespFromProto(m *subscription.SubscriptionPauseResponse) *SubscriptionPauseResponse {
	return converters.ConvertOrNil(m, func(m *subscription.SubscriptionPauseResponse) SubscriptionPauseResponse {
		return SubscriptionPauseResponse{
			Subscription: subscriptionFromProtoHelper(m.GetSubscription()),
		}
	})
}

func (s *SubscriptionPauseParameter) ToProto(baseHeader *gcontext.BaseHeader) *subscription.SubscriptionPauseRequest {
	return converters.ConvertOrNil(s, func(s *SubscriptionPauseParameter) subscription.SubscriptionPauseRequest {
		return subscription.SubscriptionPauseRequest{
			Id:               s.ID,
			TenantCustomerId: converters.ConvertOrEmpty(baseHeader, func(h *gcontext.BaseHeader) string { return h.XTenantCustomerID }),
		}
	})
}
