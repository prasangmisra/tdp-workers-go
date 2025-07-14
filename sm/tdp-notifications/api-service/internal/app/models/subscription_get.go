package models

import (
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/converters"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
)

type SubscriptionGetParameter struct {
	ID string `uri:"id" binding:"required,uuid"`
} // @name SubscriptionGetRequest

type SubscriptionGetResponse struct {
	*Subscription
} // @name SubscriptionGetResponse

func SubscriptionGetRespFromProto(m *subscription.SubscriptionGetResponse) *SubscriptionGetResponse {
	return converters.ConvertOrNil(m, func(m *subscription.SubscriptionGetResponse) SubscriptionGetResponse {
		return SubscriptionGetResponse{
			Subscription: subscriptionFromProtoHelper(m.GetSubscription()),
		}
	})
}

func (s *SubscriptionGetParameter) ToProto(baseHeader *gcontext.BaseHeader) *subscription.SubscriptionGetRequest {
	return converters.ConvertOrNil(s, func(s *SubscriptionGetParameter) subscription.SubscriptionGetRequest {
		return subscription.SubscriptionGetRequest{
			Id:               s.ID,
			TenantCustomerId: converters.ConvertOrEmpty(baseHeader, func(h *gcontext.BaseHeader) string { return h.XTenantCustomerID }),
		}
	})
}
