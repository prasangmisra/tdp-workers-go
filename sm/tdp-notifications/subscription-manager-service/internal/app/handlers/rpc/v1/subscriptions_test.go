package v1

import (
	"context"
	"errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message"
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	smerrors "github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/errors"
	handlersmock "github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/mock/rest/handlers"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"google.golang.org/protobuf/proto"
	"testing"
)

func TestCreateSubscriptionHandler(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		msg    proto.Message
		mocksF func(*handlersmock.IService, *mocks.MockMessageBusServer)

		requireErr require.ErrorAssertionFunc
	}{
		{
			name:       "success",
			msg:        &subscription.SubscriptionCreateRequest{},
			requireErr: require.NoError,

			mocksF: func(srvc *handlersmock.IService, mbsrvr *mocks.MockMessageBusServer) {
				resp := &subscription.SubscriptionCreateResponse{}
				ctx := context.Background()

				mbsrvr.On("Reply", resp, map[string]interface{}(nil)).
					Return(nil).Times(1)
				mbsrvr.On("Context").
					Return(ctx).Times(1)
				srvc.On("CreateSubscription", ctx, mock.Anything).
					Return(resp, nil).Times(1)

			},
		},
		{
			name:       "invalid message type - reply with BAD_REQUEST",
			msg:        nil,
			requireErr: require.NoError,

			mocksF: func(srvc *handlersmock.IService, mbsrvr *mocks.MockMessageBusServer) {
				mbsrvr.On("ErrorReply", message.ErrorResponse_BAD_REQUEST, mock.Anything, mock.Anything, false, nil).
					Return(nil).Times(1)
			},
		},
		{
			name:       "error - unexpected error from service",
			msg:        &subscription.SubscriptionCreateRequest{},
			requireErr: require.Error,

			mocksF: func(srvc *handlersmock.IService, mbsrvr *mocks.MockMessageBusServer) {
				ctx := context.Background()
				mbsrvr.On("Context").
					Return(ctx).Times(1)
				srvc.On("CreateSubscription", ctx, mock.Anything).
					Return(nil, errors.New("error processing entity")).Times(1)
			},
		},
		{
			name:       "error - unexpected error from message bus on Reply",
			msg:        &subscription.SubscriptionCreateRequest{},
			requireErr: require.Error,

			mocksF: func(srvc *handlersmock.IService, mbsrvr *mocks.MockMessageBusServer) {
				resp := &subscription.SubscriptionCreateResponse{}
				ctx := context.Background()

				mbsrvr.On("Reply", resp, map[string]interface{}(nil)).
					Return(errors.New("failed to reply")).Times(1)
				mbsrvr.On("Context").
					Return(ctx).Times(1)
				srvc.On("CreateSubscription", ctx, mock.Anything).
					Return(resp, nil).Times(1)
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			srvc := handlersmock.NewIService(t)
			router := NewHandler(srvc, &logger.MockLogger{})
			mbsrvr := &mocks.MockMessageBusServer{}

			if tc.mocksF != nil {
				tc.mocksF(srvc, mbsrvr)
			}

			err := router.CreateSubscriptionHandler(mbsrvr, tc.msg)
			tc.requireErr(t, err)
		})
	}
}

func TestGetSubscriptionByIDHandler(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		msg    proto.Message
		mocksF func(*handlersmock.IService, *mocks.MockMessageBusServer)

		requireErr require.ErrorAssertionFunc
	}{
		{
			name:       "success",
			msg:        &subscription.SubscriptionGetRequest{},
			requireErr: require.NoError,

			mocksF: func(srvc *handlersmock.IService, mbsrvr *mocks.MockMessageBusServer) {
				resp := &subscription.SubscriptionGetResponse{}
				ctx := context.Background()

				mbsrvr.On("Reply", resp, map[string]interface{}(nil)).
					Return(nil).Times(1)
				mbsrvr.On("Context").
					Return(ctx).Times(1)
				srvc.On("GetSubscriptionByID", ctx, mock.Anything).
					Return(resp, nil).Times(1)

			},
		},
		{
			name:       "invalid message type - reply with BAD_REQUEST",
			msg:        nil,
			requireErr: require.NoError,

			mocksF: func(srvc *handlersmock.IService, mbsrvr *mocks.MockMessageBusServer) {
				mbsrvr.On("ErrorReply", message.ErrorResponse_BAD_REQUEST, mock.Anything, mock.Anything, false, mock.Anything).
					Return(nil).Times(1)
			},
		},
		{
			name:       "subscription not found - reply with NOT_FOUND",
			msg:        &subscription.SubscriptionGetRequest{},
			requireErr: require.NoError,

			mocksF: func(srvc *handlersmock.IService, mbsrvr *mocks.MockMessageBusServer) {
				ctx := context.Background()

				mbsrvr.On("ErrorReply", message.ErrorResponse_NOT_FOUND, mock.Anything, mock.Anything, false, mock.Anything).
					Return(nil).Times(1)
				mbsrvr.On("Context").
					Return(ctx).Times(1)
				srvc.On("GetSubscriptionByID", ctx, mock.Anything).
					Return(nil, smerrors.ErrNotFound).Times(1)
			},
		},
		{
			name:       "error - unexpected error from service",
			msg:        &subscription.SubscriptionGetRequest{},
			requireErr: require.Error,

			mocksF: func(srvc *handlersmock.IService, mbsrvr *mocks.MockMessageBusServer) {
				ctx := context.Background()
				mbsrvr.On("Context").
					Return(ctx).Times(1)
				srvc.On("GetSubscriptionByID", ctx, mock.Anything).
					Return(nil, errors.New("error processing entity")).Times(1)
			},
		},
		{
			name:       "error - unexpected error from message bus on Reply",
			msg:        &subscription.SubscriptionGetRequest{},
			requireErr: require.Error,

			mocksF: func(srvc *handlersmock.IService, mbsrvr *mocks.MockMessageBusServer) {
				resp := &subscription.SubscriptionGetResponse{}
				ctx := context.Background()

				mbsrvr.On("Reply", resp, map[string]interface{}(nil)).
					Return(errors.New("failed to reply")).Times(1)
				mbsrvr.On("Context").
					Return(ctx).Times(1)
				srvc.On("GetSubscriptionByID", ctx, mock.Anything).
					Return(resp, nil).Times(1)
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			srvc := handlersmock.NewIService(t)
			router := NewHandler(srvc, &logger.MockLogger{})
			mbsrvr := &mocks.MockMessageBusServer{}

			if tc.mocksF != nil {
				tc.mocksF(srvc, mbsrvr)
			}

			err := router.GetSubscriptionByIDHandler(mbsrvr, tc.msg)
			tc.requireErr(t, err)
		})
	}
}

func TestListSubscriptionsHandler(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		msg    proto.Message
		mocksF func(*handlersmock.IService, *mocks.MockMessageBusServer)

		requireErr require.ErrorAssertionFunc
	}{
		{
			name:       "success",
			msg:        &subscription.SubscriptionListRequest{},
			requireErr: require.NoError,

			mocksF: func(srvc *handlersmock.IService, mbsrvr *mocks.MockMessageBusServer) {
				resp := &subscription.SubscriptionListResponse{}
				ctx := context.Background()

				mbsrvr.On("Reply", resp, map[string]interface{}(nil)).
					Return(nil).Times(1)
				mbsrvr.On("Context").
					Return(ctx).Times(1)
				srvc.On("ListSubscriptions", ctx, mock.Anything).
					Return(resp, nil).Times(1)

			},
		},
		{
			name:       "invalid message type - reply with BAD_REQUEST",
			msg:        nil,
			requireErr: require.NoError,

			mocksF: func(srvc *handlersmock.IService, mbsrvr *mocks.MockMessageBusServer) {
				mbsrvr.On("ErrorReply", message.ErrorResponse_BAD_REQUEST, mock.Anything, mock.Anything, false, nil).
					Return(nil).Times(1)
			},
		},
		{
			name:       "error - unexpected error from service",
			msg:        &subscription.SubscriptionListRequest{},
			requireErr: require.Error,

			mocksF: func(srvc *handlersmock.IService, mbsrvr *mocks.MockMessageBusServer) {
				ctx := context.Background()
				mbsrvr.On("Context").
					Return(ctx).Times(1)
				srvc.On("ListSubscriptions", ctx, mock.Anything).
					Return(nil, errors.New("error processing entity")).Times(1)
			},
		},
		{
			name:       "error - unexpected error from message bus on Reply",
			msg:        &subscription.SubscriptionListRequest{},
			requireErr: require.Error,

			mocksF: func(srvc *handlersmock.IService, mbsrvr *mocks.MockMessageBusServer) {
				resp := &subscription.SubscriptionListResponse{}
				ctx := context.Background()

				mbsrvr.On("Reply", resp, map[string]interface{}(nil)).
					Return(errors.New("failed to reply")).Times(1)
				mbsrvr.On("Context").
					Return(ctx).Times(1)
				srvc.On("ListSubscriptions", ctx, mock.Anything).
					Return(resp, nil).Times(1)
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			srvc := handlersmock.NewIService(t)
			router := NewHandler(srvc, &logger.MockLogger{})
			mbsrvr := &mocks.MockMessageBusServer{}

			if tc.mocksF != nil {
				tc.mocksF(srvc, mbsrvr)
			}

			err := router.ListSubscriptionsHandler(mbsrvr, tc.msg)
			tc.requireErr(t, err)
		})
	}
}
