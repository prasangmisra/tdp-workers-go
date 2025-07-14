package service_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	tcwire "github.com/tucowsinc/tdp-messages-go/message"
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/app/models"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/app/service"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestResumeSubscription(t *testing.T) {
	t.Parallel()

	const subscriptionQueue = "subscriptionQueue"
	metadataToProtoSafe := func(t *testing.T, metadata map[string]interface{}) map[string]*anypb.Any {
		protoMetadata, err := models.MetadataToProto(metadata)
		require.NoError(t, err)
		return protoMetadata
	}

	metadata := map[string]interface{}{"key1": "value1"}
	metadataProto := metadataToProtoSafe(t, metadata)

	subscriptionID := "test-subscription-id"
	now := time.Now().UTC()

	tests := []struct {
		name         string
		msg          proto.Message
		baseHeader   *gcontext.BaseHeader
		req          models.SubscriptionResumeParameter
		headers      map[string]any
		mocksF       func(mb *mocks.MockMessageBus, resp messagebus.RpcResponse)
		expectedResp *models.SubscriptionResumeResponse
		errAssertion require.ErrorAssertionFunc
	}{
		{
			name: "happy path",
			msg: &subscription.SubscriptionResumeResponse{
				Subscription: &subscription.SubscriptionDetailsResponse{
					Id:                subscriptionID,
					NotificationEmail: "test@example.com",
					Url:               "https://webhook.com",
					Status:            subscription.SubscriptionStatus_PAUSED,
					Tags:              []string{"tag1", "tag2"},
					Metadata:          metadataProto,
					NotificationTypes: []string{"DOMAIN_CREATED"},
					CreatedDate:       timestamppb.New(now),
					UpdatedDate:       timestamppb.New(now),
				},
			},
			mocksF: func(mb *mocks.MockMessageBus, resp messagebus.RpcResponse) {
				mb.On("Call", mock.Anything, subscriptionQueue, mock.Anything, mock.Anything).
					Return("expMsgId", resp, nil)
			},
			expectedResp: &models.SubscriptionResumeResponse{
				Subscription: &models.Subscription{
					ID:                subscriptionID,
					NotificationEmail: "test@example.com",
					URL:               "https://webhook.com",
					Status:            models.Paused,
					Tags:              []string{"tag1", "tag2"},
					Metadata:          metadata,
					NotificationTypes: []string{"DOMAIN_CREATED"},
					CreatedDate:       &now,
					UpdatedDate:       &now,
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
			name: "unexpected message type",
			msg:  nil,
			mocksF: func(mb *mocks.MockMessageBus, resp messagebus.RpcResponse) {
				mb.On("Call", mock.Anything, subscriptionQueue, mock.Anything, mock.Anything).
					Return("expMsgId", resp, nil)
			},
			expectedResp: nil,
			errAssertion: require.Error,
		},
		{
			name: "message bus internal error",
			mocksF: func(mb *mocks.MockMessageBus, resp messagebus.RpcResponse) {
				mb.On("Call", mock.Anything, subscriptionQueue, mock.Anything, mock.Anything).
					Return("expMsgId", nil, errors.New("message bus internal error"))
			},
			expectedResp: nil,
			errAssertion: require.Error,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			// Mock message bus
			mb := &mocks.MockMessageBus{}
			if tc.mocksF != nil {
				tc.mocksF(mb, messagebus.RpcResponse{Message: tc.msg})
			}

			// Prepare service instance
			s := service.New(mb, subscriptionQueue)

			// Call the ResumeSubscription method
			resp, err := s.ResumeSubscription(context.Background(), &tc.req, tc.headers, tc.baseHeader)

			// Assert results
			tc.errAssertion(t, err)
			require.Equal(t, tc.expectedResp, resp)
		})
	}
}
