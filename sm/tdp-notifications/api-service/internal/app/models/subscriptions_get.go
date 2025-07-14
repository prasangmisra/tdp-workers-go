package models

import (
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/converters"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
)

type SubscriptionsGetParameter struct {
	Pagination
} // @name SubscriptionsGetParameter

type SubscriptionsGetResponse struct {
	Items []*Subscription `json:"items"`
	PagedViewModel
} // @name SubscriptionsGetResponse

func (s *SubscriptionsGetParameter) ToProto(baseHeader *gcontext.BaseHeader) *subscription.SubscriptionListRequest {
	return converters.ConvertOrNil(s, func(s *SubscriptionsGetParameter) subscription.SubscriptionListRequest {
		return subscription.SubscriptionListRequest{
			TenantCustomerId: converters.ConvertOrEmpty(baseHeader, func(h *gcontext.BaseHeader) string { return h.XTenantCustomerID }),
			Pagination:       s.Pagination.ToProto(),
		}
	})
}

func SubscriptionsGetRespFromProto(m *subscription.SubscriptionListResponse, pagination *Pagination, totalCount int) *SubscriptionsGetResponse {
	return converters.ConvertOrNil(m, func(m *subscription.SubscriptionListResponse) SubscriptionsGetResponse {
		subscriptionsGetResponse := SubscriptionsGetResponse{
			Items: make([]*Subscription, len(m.Subscriptions)),
			PagedViewModel: PagedViewModel{
				PageSize:        pagination.GetPageSize(),
				PageNumber:      pagination.GetPageNumber(),
				TotalCount:      totalCount,
				TotalPages:      pagination.GetTotalPages(totalCount),
				HasNextPage:     pagination.HasNextPage(totalCount),
				HasPreviousPage: pagination.HasPreviousPage(),
			},
		}

		for i, subscription := range m.Subscriptions {
			subscriptionsGetResponse.Items[i] = subscriptionFromProtoHelper(subscription)
		}

		return subscriptionsGetResponse
	})
}
