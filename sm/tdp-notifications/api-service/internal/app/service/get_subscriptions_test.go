package service

import (
	"context"
	"errors"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	tcwire "github.com/tucowsinc/tdp-messages-go/message"
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/app/models"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
	"google.golang.org/protobuf/proto"
)

func TestGetSubscriptions(t *testing.T) {
	t.Parallel()

	const subscriptionQueue = "subscriptionQueue"

	tests := []struct {
		name         string
		msg          proto.Message
		baseHeader   *gcontext.BaseHeader
		req          models.SubscriptionsGetParameter
		headers      map[string]any
		mocksF       func(mb *mocks.MockMessageBus, resp messagebus.RpcResponse)
		expectedResp *models.SubscriptionsGetResponse
		errAssertion require.ErrorAssertionFunc
	}{
		{
			name: "happy path",
			req: models.SubscriptionsGetParameter{
				Pagination: models.Pagination{
					PageSize:   10,
					PageNumber: 1,
				},
			},
			msg: &subscription.SubscriptionListResponse{
				Subscriptions: []*subscription.SubscriptionDetailsResponse{
					{
						Id:                "subscription_id_1",
						Url:               "https://webhook1.com",
						NotificationTypes: []string{"DOMAIN_CREATED"},
					},
					{
						Id:                "subscription_id_2",
						Url:               "https://webhook2.com",
						NotificationTypes: []string{"CONTACT_CREATED"},
					},
				},
				TotalCount: 2,
			},
			mocksF: func(mb *mocks.MockMessageBus, resp messagebus.RpcResponse) {
				mb.On("Call", mock.Anything, subscriptionQueue, mock.Anything, mock.Anything).
					Return("expMsgId", resp, nil)
			},
			expectedResp: &models.SubscriptionsGetResponse{
				Items: []*models.Subscription{
					{
						ID:                "subscription_id_1",
						URL:               "https://webhook1.com",
						NotificationTypes: []string{"DOMAIN_CREATED"},
						Status:            models.Active,
					},
					{
						ID:                "subscription_id_2",
						URL:               "https://webhook2.com",
						NotificationTypes: []string{"CONTACT_CREATED"},
						Status:            models.Active,
					},
				},
				PagedViewModel: models.PagedViewModel{
					PageSize:        10,
					PageNumber:      1,
					TotalCount:      2,
					TotalPages:      1,
					HasNextPage:     false,
					HasPreviousPage: false,
				},
			},
			errAssertion: require.NoError,
		},
		{
			name: "message bus - tcwire ErrorResponse",
			msg:  &tcwire.ErrorResponse{Message: "Internal Server Error", AppCode: tcwire.ErrorResponse_FAILED_OPERATION},
			mocksF: func(mb *mocks.MockMessageBus, resp messagebus.RpcResponse) {
				mb.On("Call", mock.Anything, subscriptionQueue, mock.Anything, mock.Anything).
					Return("expMsgId", resp, nil)
			},
			expectedResp: nil,
			errAssertion: require.Error,
		},
		{
			name: "message bus - error on Call",
			mocksF: func(mb *mocks.MockMessageBus, resp messagebus.RpcResponse) {
				mb.On("Call", mock.Anything, subscriptionQueue, mock.Anything, mock.Anything).
					Return("expMsgId", nil, errors.New("message bus internal error"))
			},
			expectedResp: nil,
			errAssertion: require.Error,
		},
		{
			name: "message bus - unexpected message type",
			msg:  nil,
			mocksF: func(mb *mocks.MockMessageBus, resp messagebus.RpcResponse) {
				mb.On("Call", mock.Anything, subscriptionQueue, mock.Anything, mock.Anything).
					Return("expMsgId", resp, nil)
			},
			expectedResp: nil,
			errAssertion: require.Error,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			mb := &mocks.MockMessageBus{}
			if tc.mocksF != nil {
				tc.mocksF(mb, messagebus.RpcResponse{Message: tc.msg})
			}

			s := New(mb, subscriptionQueue)
			resp, err := s.GetSubscriptions(context.Background(), &tc.req, tc.headers, tc.baseHeader)
			tc.errAssertion(t, err)
			require.Equal(t, tc.expectedResp, resp)
		})
	}
}
