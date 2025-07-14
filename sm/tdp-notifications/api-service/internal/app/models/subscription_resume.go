package models

import (
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/converters"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
)

type SubscriptionResumeParameter struct {
	ID string `uri:"id" binding:"required,uuid"`
} // @name SubscriptionResumeParameter

type SubscriptionResumeResponse struct {
	*Subscription
} // @name SubscriptionResumeResponse

func SubscriptionResumeRespFromProto(m *subscription.SubscriptionResumeResponse) *SubscriptionResumeResponse {
	return converters.ConvertOrNil(m, func(m *subscription.SubscriptionResumeResponse) SubscriptionResumeResponse {
		return SubscriptionResumeResponse{
			Subscription: subscriptionFromProtoHelper(m.GetSubscription()),
		}
	})
}

func (s *SubscriptionResumeParameter) ToProto(baseHeader *gcontext.BaseHeader) *subscription.SubscriptionResumeRequest {
	return converters.ConvertOrNil(s, func(s *SubscriptionResumeParameter) subscription.SubscriptionResumeRequest {
		return subscription.SubscriptionResumeRequest{
			Id: s.ID,
			TenantCustomerId: converters.ConvertOrEmpty(baseHeader, func(h *gcontext.BaseHeader) string {
				return h.XTenantCustomerID
			}),
		}
	})
}
