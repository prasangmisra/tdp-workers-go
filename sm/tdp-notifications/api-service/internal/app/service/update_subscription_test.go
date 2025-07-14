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

func TestUpdateSubscription(t *testing.T) {
	t.Parallel()

	const subscriptionQueue = "subscriptionQueue"

	tests := []struct {
		name       string
		msg        proto.Message
		baseHeader *gcontext.BaseHeader
		s          models.SubscriptionUpdateRequest
		headers    map[string]any
		mocksF     func(mb *mocks.MockMessageBus, resp messagebus.RpcResponse)

		expectedResp *models.SubscriptionUpdateResponse
		errAssertion require.ErrorAssertionFunc
	}{
		{
			name: "happy path",
			msg: &subscription.SubscriptionUpdateResponse{
				Subscription: &subscription.SubscriptionDetailsResponse{
					Id:                "subscription_id",
					Url:               "https://webhook.com",
					NotificationTypes: []string{"CONTACT_CREATED", "DOMAIN_CREATED"},
				},
			},
			mocksF: func(mb *mocks.MockMessageBus, resp messagebus.RpcResponse) {
				mb.On("Call", mock.Anything, subscriptionQueue, mock.Anything, mock.Anything).
					Return("expMsgId", resp, nil)
			},

			expectedResp: &models.SubscriptionUpdateResponse{
				Subscription: &models.Subscription{
					ID:                "subscription_id",
					URL:               "https://webhook.com",
					Status:            models.Active,
					NotificationTypes: []string{"CONTACT_CREATED", "DOMAIN_CREATED"},
				},
			},
			errAssertion: require.NoError,
		},
		{
			name: "subscription not found",
			msg:  &tcwire.ErrorResponse{Message: "Subscription not found", AppCode: tcwire.ErrorResponse_NOT_FOUND},
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

			errAssertion: require.Error,
		},
		{
			name: "message bus - unexpected message type",
			msg:  nil,
			mocksF: func(mb *mocks.MockMessageBus, resp messagebus.RpcResponse) {
				mb.On("Call", mock.Anything, subscriptionQueue, mock.Anything, mock.Anything).
					Return("expMsgId", resp, nil)
			},

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
			resp, err := s.UpdateSubscription(context.Background(), &tc.s, tc.headers, tc.baseHeader)
			tc.errAssertion(t, err)
			require.Equal(t, tc.expectedResp, resp)
		})
	}
}
