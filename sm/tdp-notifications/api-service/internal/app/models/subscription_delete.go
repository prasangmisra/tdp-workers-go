package models

import (
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/converters"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
)

type SubscriptionDeleteParameter struct {
	ID string `uri:"id" binding:"required,uuid"`
} // @name SubscriptionDeleteParameter

func (s *SubscriptionDeleteParameter) ToProto(baseHeader *gcontext.BaseHeader) *subscription.SubscriptionDeleteRequest {
	return converters.ConvertOrNil(s, func(s *SubscriptionDeleteParameter) subscription.SubscriptionDeleteRequest {
		return subscription.SubscriptionDeleteRequest{
			Id:               s.ID,
			TenantCustomerId: converters.ConvertOrEmpty(baseHeader, func(h *gcontext.BaseHeader) string { return h.XTenantCustomerID }),
		}
	})
}
