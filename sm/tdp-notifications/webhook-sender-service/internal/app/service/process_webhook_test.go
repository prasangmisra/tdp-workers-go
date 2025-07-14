package service

import (
	"context"
	"fmt"
	"github.com/samber/lo"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	proto "github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/app/config"
	mocks "github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/app/mock"
	"github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/pkg/rest"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"
	_ "google.golang.org/protobuf/types/known/structpb"
	"testing"
)

func TestExtractPayload(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name       string
		req        *proto.Notification
		expected   []byte
		requireErr require.ErrorAssertionFunc
	}{
		{
			name:       "Nil WebhookUrl",
			req:        &proto.Notification{SigningSecret: lo.ToPtr("secret")},
			requireErr: require.Error,
		},
		{
			name:       "Nil SigningSecret",
			req:        &proto.Notification{WebhookUrl: lo.ToPtr("https://test.com")},
			requireErr: require.Error,
		},
		{
			name: "Invalid data",
			req: &proto.Notification{
				WebhookUrl:    lo.ToPtr("https://test.com"),
				SigningSecret: lo.ToPtr("secret"),
				Data:          &anypb.Any{},
			},
			requireErr: require.Error,
		},
		{
			name: "Nil data",
			req: &proto.Notification{
				WebhookUrl:    lo.ToPtr("https://test.com"),
				SigningSecret: lo.ToPtr("secret"),
			},
			expected:   []byte(`{}`),
			requireErr: require.NoError,
		},
		{
			name: "Valid JSON req",
			req: &proto.Notification{
				WebhookUrl:    lo.ToPtr("https://test.com"),
				SigningSecret: lo.ToPtr("secret"),
				Data: func() *anypb.Any {
					// Create a protobuf Struct representing {"key": "value"}
					structData := &structpb.Struct{
						Fields: map[string]*structpb.Value{
							"key": structpb.NewStringValue("value"),
						},
					}
					// Pack structData into anypb.Any
					anyData, err := anypb.New(structData)
					require.NoError(t, err, "Failed to create *anypb.Any")
					return anyData
				}(),
			},
			expected:   []byte(`{"payload":{"key":"value"}}`),
			requireErr: require.NoError,
		},
		{
			name: "Complex JSON req",
			req: &proto.Notification{
				WebhookUrl:    lo.ToPtr("https://test.com"),
				SigningSecret: lo.ToPtr("secret"),
				Data: func() *anypb.Any {
					// Create a nested protobuf Struct
					structData := &structpb.Struct{
						Fields: map[string]*structpb.Value{
							"key1": structpb.NewStringValue("value1"),
							"key2": structpb.NewStructValue(&structpb.Struct{
								Fields: map[string]*structpb.Value{
									"nestedKey": structpb.NewStringValue("nestedValue"),
								},
							}),
						},
					}
					// Pack structData into anypb.Any
					anyData, err := anypb.New(structData)
					require.NoError(t, err, "Failed to create *anypb.Any")
					return anyData
				}(),
			},
			expected:   []byte(`{"payload":{"key1":"value1","key2":{"nestedKey":"nestedValue"}}}`),
			requireErr: require.NoError,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			service := Service{Logger: &logger.MockLogger{}}

			payload, err := service.validateRequest(tt.req)
			tt.requireErr(t, err)
			require.Equal(t, string(tt.expected), string(payload))
		})
	}
}

func TestProcessWebhook(t *testing.T) {
	mockBus := new(mocks.MockMessageBus)

	tests := []struct {
		name       string
		req        *proto.Notification
		retryCount int
		wantErr    require.ErrorAssertionFunc
		setupMocks func(service *Service, mockBus *mocks.MockMessageBus, mockHTTPClient *mocks.IHTTPClient)
	}{
		{
			name: "Req is nil",
			req:  nil,
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.Error(t, err)
				require.Equal(t, "received nil request", err.Error())
			},
		},
		{
			name:       "CanSend is false and error from PublishToFinalStatusQueue",
			req:        &proto.Notification{},
			retryCount: 5,
			setupMocks: func(service *Service, mockBus *mocks.MockMessageBus, mockHTTPClient *mocks.IHTTPClient) {
				service.Bus = nil
			},
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.Error(t, err)
				require.Equal(t, "message bus not initialized to publish to final status queue", err.Error())
			},
		},
		{
			name:       "CanSend is false and error from PublishToFinalStatusQueue sending message",
			req:        &proto.Notification{},
			retryCount: 5,
			setupMocks: func(service *Service, mockBus *mocks.MockMessageBus, mockHTTPClient *mocks.IHTTPClient) {
				mockBus.On("Send", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
					Return("", fmt.Errorf("No Listener")).Once() // ✅ Mock a successful message send
			},
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.Error(t, err)
				require.Equal(t, "failed to send message to queue final_queue: No Listener", err.Error())
			},
		},
		{
			name: "CanSend is true and webhookURL is nil, bus is nil",
			req: &proto.Notification{
				WebhookUrl: nil,
			},
			setupMocks: func(service *Service, mockBus *mocks.MockMessageBus, mockHTTPClient *mocks.IHTTPClient) {
				service.Bus = nil
			},
			retryCount: 2,
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.Error(t, err)
				require.Equal(t, "message bus not initialized to publish to final status queue", err.Error())
			},
		},
		{
			name: "extractPayload returns error",
			req: &proto.Notification{
				WebhookUrl: lo.ToPtr("http://www.example.com"),
				Data: &anypb.Any{ // Malformed Protobuf Any
					TypeUrl: "type.googleapis.com/google.protobuf.Struct", // Incorrect type
					Value:   []byte("invalid data"),                       // Random non-struct bytes
				},
			},
			retryCount: 2,
			setupMocks: func(service *Service, mockBus *mocks.MockMessageBus, mockHTTPClient *mocks.IHTTPClient) {
				service.Bus = nil
			},
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.Error(t, err)
				require.Contains(t, err.Error(), "message bus not initialized to publish to final status queue")
			},
		},
		{
			name: "SigningSecret is nil",
			req: &proto.Notification{
				WebhookUrl: lo.ToPtr("http://www.example.com"),
			},
			retryCount: 2,
			setupMocks: func(service *Service, mockBus *mocks.MockMessageBus, mockHTTPClient *mocks.IHTTPClient) {
				service.Bus = nil
			},
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.Error(t, err)
				require.Contains(t, err.Error(), "message bus not initialized to publish to final status queue")
			},
		},
		{
			name: "HTTPClient returns error and ShouldRetry is true",
			req: &proto.Notification{
				WebhookUrl:    lo.ToPtr("http://www.example.com"),
				SigningSecret: lo.ToPtr("abcd"),
			},
			retryCount: 2,
			setupMocks: func(service *Service, mockBus *mocks.MockMessageBus, mockHTTPClient *mocks.IHTTPClient) {
				// Mocking HTTP client to return error
				mockHTTPClient.On("SendPostRequest", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
					Return(0, rest.ErrNetwork).Once()

				mockBus.On("Send", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
					Return("", fmt.Errorf("No Listener")).Once() // ✅ Mock a successful message send

				service.HTTPClient = mockHTTPClient
			},
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.Error(t, err)
				require.Contains(t, err.Error(), "failed to send message to queue retry-queue-3: No Listener")
			},
		},
		{
			name: "HTTPClient returns error and ShouldRetry is false",
			req: &proto.Notification{
				WebhookUrl:    lo.ToPtr("http://www.example.com"),
				SigningSecret: lo.ToPtr("abcd"),
			},
			retryCount: 1,
			setupMocks: func(service *Service, mockBus *mocks.MockMessageBus, mockHTTPClient *mocks.IHTTPClient) {
				// Mocking HTTP client to return error
				mockHTTPClient.On("SendPostRequest", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
					Return(0, fmt.Errorf("Some Error")).Once()

				mockBus.On("Send", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
					Return("", fmt.Errorf("No Listener")).Once() // ✅ Mock a successful message send

				service.HTTPClient = mockHTTPClient
			},
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.Error(t, err)
				require.Contains(t, err.Error(), "failed to send message to queue final_queue: No Listener")
			},
		},
		{
			name: "HTTPClient returns status code 500 error",
			req: &proto.Notification{
				WebhookUrl:    lo.ToPtr("http://www.example.com"),
				SigningSecret: lo.ToPtr("abcd"),
			},
			retryCount: 2,
			setupMocks: func(service *Service, mockBus *mocks.MockMessageBus, mockHTTPClient *mocks.IHTTPClient) {
				// Mocking HTTP client to return status 500
				mockHTTPClient.On("SendPostRequest", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
					Return(500, nil).Once()

				service.HTTPClient = mockHTTPClient

				mockBus.On("Send", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
					Return("", nil).Once() // ✅ Mock a successful message send
			},
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.NoError(t, err) // No retry needed, so error is handled gracefully
			},
		},
		{
			name: "HTTPClient returns status code 400 (client error)",
			req: &proto.Notification{
				WebhookUrl:    lo.ToPtr("http://www.example.com"),
				SigningSecret: lo.ToPtr("abcd"),
			},
			retryCount: 2,
			setupMocks: func(service *Service, mockBus *mocks.MockMessageBus, mockHTTPClient *mocks.IHTTPClient) {
				// Mocking HTTP client to return status 400
				mockHTTPClient.On("SendPostRequest", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
					Return(400, nil).Once()

				service.HTTPClient = mockHTTPClient

				mockBus.On("Send", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
					Return("", nil).Once() // ✅ Mock a successful message send
			},
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.NoError(t, err) // No retry needed, so error is handled gracefully
			},
		},
		{
			name: "HTTPClient returns status code 300 (redirection error)",
			req: &proto.Notification{
				WebhookUrl:    lo.ToPtr("http://www.example.com"),
				SigningSecret: lo.ToPtr("abcd"),
			},
			retryCount: 2,
			setupMocks: func(service *Service, mockBus *mocks.MockMessageBus, mockHTTPClient *mocks.IHTTPClient) {
				// Mocking HTTP client to return status 300
				mockHTTPClient.On("SendPostRequest", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
					Return(300, nil).Once()

				service.HTTPClient = mockHTTPClient

				mockBus.On("Send", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
					Return("", nil).Once() // ✅ Mock a successful message send
			},
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.NoError(t, err) // No retry needed, so error is handled gracefully
			},
		},
		{
			name: "HTTPClient works fine (status 200)",
			req: &proto.Notification{
				WebhookUrl:    lo.ToPtr("http://www.example.com"),
				SigningSecret: lo.ToPtr("abcd"),
			},
			retryCount: 2,
			setupMocks: func(service *Service, mockBus *mocks.MockMessageBus, mockHTTPClient *mocks.IHTTPClient) {
				// Mocking HTTP client to return status 200
				mockHTTPClient.On("SendPostRequest", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
					Return(200, nil).Once()

				service.HTTPClient = mockHTTPClient
				mockBus.On("Send", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
					Return("", nil).Once() // ✅ Mock a successful message send
			},
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.NoError(t, err)
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			mockLogger := &mocks.MockLogger{}
			mockHTTPClient := new(mocks.IHTTPClient)
			service := &Service{
				FinalStatusQueue: "final_queue",
				Cfg: &config.Config{RMQ: config.RMQ{
					RetryQueues: []config.RetryQueue{
						{Name: "retry-queue", TTL: 60},
						{Name: "retry-queue-2", TTL: 120},
						{Name: "retry-queue-3", TTL: 180},
					},
				}},
				Logger:     mockLogger,
				Bus:        mockBus,
				HTTPClient: mockHTTPClient,
			}
			if tc.setupMocks != nil {
				tc.setupMocks(service, mockBus, mockHTTPClient)
			}

			err := service.ProcessWebhook(context.Background(), tc.req, tc.retryCount)
			// ✅ Verify expected error response
			tc.wantErr(t, err)

			// ✅ Ensure all expected mock calls happened
			mockBus.AssertExpectations(t)
		})
	}
}
