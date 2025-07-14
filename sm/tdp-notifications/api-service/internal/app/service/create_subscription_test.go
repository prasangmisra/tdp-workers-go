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

func TestCreateSubscription(t *testing.T) {
	t.Parallel()

	const subscriptionQueue = "subscriptionQueue"

	tests := []struct {
		name       string
		msg        proto.Message
		baseHeader *gcontext.BaseHeader
		s          models.SubscriptionCreateRequest
		headers    map[string]any
		mocksF     func(mb *mocks.MockMessageBus, resp messagebus.RpcResponse)

		expectedResp *models.SubscriptionCreateResponse
		errAssertion require.ErrorAssertionFunc
	}{
		{
			name: "happy path",
			msg: &subscription.SubscriptionCreateResponse{
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

			expectedResp: &models.SubscriptionCreateResponse{
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
			name: "message bus - tcwire ErrorResponse",
			msg:  &tcwire.ErrorResponse{Message: "Subscription already exists", AppCode: tcwire.ErrorResponse_ALREADY_EXISTS},
			mocksF: func(mb *mocks.MockMessageBus, resp messagebus.RpcResponse) {
				mb.On("Call", mock.Anything, subscriptionQueue, mock.Anything, mock.Anything).
					Return("expMsgId", resp, nil)
			},

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
			resp, err := s.CreateSubscription(context.Background(), &tc.s, tc.headers, tc.baseHeader)
			tc.errAssertion(t, err)
			require.Equal(t, tc.expectedResp, resp)
		})
	}
}
