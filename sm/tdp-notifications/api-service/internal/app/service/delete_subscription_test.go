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

func TestDeleteSubscription(t *testing.T) {
	t.Parallel()

	const subscriptionQueue = "subscriptionQueue"

	tests := []struct {
		name         string
		msg          proto.Message
		baseHeader   *gcontext.BaseHeader
		s            models.SubscriptionDeleteParameter
		headers      map[string]any
		mocksF       func(mb *mocks.MockMessageBus, resp messagebus.RpcResponse)
		errAssertion require.ErrorAssertionFunc
	}{
		{
			name: "happy path",
			msg:  &subscription.SubscriptionDeleteResponse{},
			mocksF: func(mb *mocks.MockMessageBus, resp messagebus.RpcResponse) {
				mb.On("Call", mock.Anything, subscriptionQueue, mock.Anything, mock.Anything).
					Return("expMsgId", resp, nil)
			},
			errAssertion: require.NoError,
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
		{
			name: "subscription not found",
			msg:  &tcwire.ErrorResponse{Message: "Subscription not found", AppCode: tcwire.ErrorResponse_NOT_FOUND},
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
			err := s.DeleteSubscription(context.Background(), &tc.s, tc.headers, tc.baseHeader)
			tc.errAssertion(t, err)
		})
	}
}
