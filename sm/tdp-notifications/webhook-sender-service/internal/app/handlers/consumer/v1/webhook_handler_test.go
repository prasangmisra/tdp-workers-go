package v1

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message"
	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	internalMock "github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/app/mock"
	"github.com/tucowsinc/tdp-shared-go/logger"
)

// ✅ Table-driven test for ProcessWebhookHandler
func TestProcessWebhookHandler(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		msg     proto.Message
		mocksF  func(*internalMock.IService, *mocks.MockMessageBusServer)
		wantErr require.ErrorAssertionFunc
	}{
		{
			name: "Message is nil",
			msg:  nil,
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.Error(t, err)
				require.Equal(t, "received nil msg", err.Error())
			},
		},
		{
			name: "Invalid Message Type",
			msg:  &datamanager.PollNotificationGetRequest{}, // ✅ A valid proto.Message that isn't datamanager.Notification
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.Error(t, err)
				require.Equal(t, "received invalid webhook notification message", err.Error())
			},
		},
		{
			name: "Invalid x_retry header - cannot be unmarshalled",
			msg: &datamanager.Notification{
				Id:          "valid-id",
				Type:        "test-event",
				TenantId:    "tenant-123",
				WebhookUrl:  proto.String("https://webhook.site/test"),
				CreatedDate: timestamppb.Now(),
				Data:        &anypb.Any{},
			},
			mocksF: func(srvc *internalMock.IService, mbus *mocks.MockMessageBusServer) {
				headers := make(map[string]*anypb.Any)
				invalidRetryValue := &anypb.Any{}
				headers["x_retry"] = invalidRetryValue

				mbus.On("Envelope").Return(&message.TcWire{Headers: headers}).Times(1)

			},
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.Error(t, err)
				expectedErr := "proto: mismatched message type: got \"google.protobuf.StringValue\", want \"\""
				actualErr := strings.ReplaceAll(err.Error(), "\u00a0", " ")
				require.Equal(t, expectedErr, actualErr)

			},
		},
		{
			name: "Invalid x_retry header - non-string value (number)",
			msg: &datamanager.Notification{
				Id:          "valid-id",
				Type:        "test-event",
				TenantId:    "tenant-123",
				WebhookUrl:  proto.String("https://webhook.site/test"),
				CreatedDate: timestamppb.Now(),
				Data:        &anypb.Any{},
			},
			mocksF: func(srvc *internalMock.IService, mbus *mocks.MockMessageBusServer) {

				headers := make(map[string]*anypb.Any)
				invalidRetryValue, err := anypb.New(&wrapperspb.Int32Value{Value: 3})
				require.NoError(t, err)
				headers["x_retry"] = invalidRetryValue

				mbus.On("Envelope").Return(&message.TcWire{Headers: headers}).Times(1)
			},

			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.Error(t, err)
				expectedErr := "proto: mismatched message type: got \"google.protobuf.StringValue\", want \"google.protobuf.Int32Value\""
				actualErr := strings.ReplaceAll(err.Error(), "\u00a0", " ")
				require.Equal(t, expectedErr, actualErr)
			},
		},
		{
			name: "Invalid x_retry header - non-integer value",
			msg: &datamanager.Notification{
				Id:          "valid-id",
				Type:        "test-event",
				TenantId:    "tenant-123",
				WebhookUrl:  proto.String("https://webhook.site/test"),
				CreatedDate: timestamppb.Now(),
				Data:        &anypb.Any{},
			},
			mocksF: func(srvc *internalMock.IService, mbus *mocks.MockMessageBusServer) {
				headers := make(map[string]*anypb.Any)

				invalidRetryValue, err := anypb.New(&wrapperspb.StringValue{Value: "abcd"})
				require.NoError(t, err)
				headers["x_retry"] = invalidRetryValue

				mbus.On("Envelope").Return(&message.TcWire{Headers: headers}).Times(1)
			},

			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.Error(t, err)
				require.Equal(t, "strconv.Atoi: parsing \"abcd\": invalid syntax", err.Error())
			},
		},
		{
			name: "Valid Notification - x_retry header set to 4 - ProcessWebhook fails",
			msg: &datamanager.Notification{
				Id:          "valid-id",
				Type:        "test-event",
				TenantId:    "tenant-123",
				WebhookUrl:  proto.String("https://webhook.site/test"),
				CreatedDate: timestamppb.Now(),
				Data:        &anypb.Any{},
			},
			mocksF: func(srvc *internalMock.IService, mbus *mocks.MockMessageBusServer) {
				ctx := context.Background()

				// ✅ Mock the Envelope() method to return a *message.TcWire with the correct headers type
				headers := make(map[string]*anypb.Any)
				retryValue, err := anypb.New(&wrapperspb.StringValue{Value: "4"}) // ✅ Correct fix
				require.NoError(t, err)
				headers["x_retry"] = retryValue

				mbus.On("Envelope").Return(&message.TcWire{Headers: headers}).Times(1)

				// ✅ Mock Context()
				mbus.On("Context").Return(ctx).Times(1)

				// ✅ Mock ProcessWebhook to return an error
				srvc.On("ProcessWebhook", ctx, mock.AnythingOfType("*datamanager.Notification"), 4).
					Return(errors.New("failed to process webhook")).Times(1)
			},
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.Error(t, err)
				require.Equal(t, "failed to process webhook", err.Error())
			},
		},
		{
			name: "Valid Notification - x_retry header set to 2 - ProcessWebhook succeeds",
			msg: &datamanager.Notification{
				Id:          "valid-id",
				Type:        "test-event",
				TenantId:    "tenant-123",
				WebhookUrl:  proto.String("https://webhook.site/test"),
				CreatedDate: timestamppb.Now(),
				Data:        &anypb.Any{},
			},
			mocksF: func(srvc *internalMock.IService, mbus *mocks.MockMessageBusServer) {
				ctx := context.Background()

				// ✅ Mock the Envelope() method to return a *message.TcWire with the correct headers type
				headers := make(map[string]*anypb.Any)
				retryValue, err := anypb.New(&wrapperspb.StringValue{Value: "2"})
				require.NoError(t, err)
				headers["x_retry"] = retryValue

				mbus.On("Envelope").Return(&message.TcWire{Headers: headers}).Times(1)

				// ✅ Mock Context()
				mbus.On("Context").Return(ctx).Times(1)

				// ✅ Mock ProcessWebhook to return an error
				srvc.On("ProcessWebhook", ctx, mock.AnythingOfType("*datamanager.Notification"), 2).
					Return(nil).Times(1)
			},
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.NoError(t, err)
			},
		},
		{
			name: "Valid Notification - x_retry header not set",
			msg:  &datamanager.Notification{},
			mocksF: func(srvc *internalMock.IService, mbus *mocks.MockMessageBusServer) {
				ctx := context.Background()
				mbus.On("Envelope").Return(&message.TcWire{Headers: nil}).Times(1)
				// ✅ Mock Context()
				mbus.On("Context").Return(ctx).Times(1)
				// ✅ Mock ProcessWebhook to return an error
				srvc.On("ProcessWebhook", ctx, mock.AnythingOfType("*datamanager.Notification"), 0).
					Return(nil).Times(1)
			},
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.NoError(t, err)
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			// Mock dependencies
			srvc := internalMock.NewIService(t)
			router := NewHandler(srvc, &logger.MockLogger{})
			mbus := &mocks.MockMessageBusServer{}

			// Set up mocks
			if tc.mocksF != nil {
				tc.mocksF(srvc, mbus)
			}

			// Execute handler
			err := router.ProcessWebhookHandler(mbus, tc.msg)
			tc.wantErr(t, err)

			// Verify expectations
			srvc.AssertExpectations(t)
			mbus.AssertExpectations(t)
		})
	}
}
