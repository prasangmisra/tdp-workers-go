package service

import (
	"context"
	"fmt"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	mocks "github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/app/mock"
)

func TestPublishToFinalStatusQueue(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name       string
		req        *datamanager.Notification
		setupMocks func(service *Service, mockBus *mocks.MockMessageBus)
		wantErr    require.ErrorAssertionFunc
		assertLogs func(t *testing.T, logs []string)
	}{
		{
			name: "Service bus is nil",
			req:  &datamanager.Notification{Id: "notif123", Status: datamanager.DeliveryStatus_FAILED},
			setupMocks: func(service *Service, mockBus *mocks.MockMessageBus) {
				service.Bus = nil
			},
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.Error(t, err)
				require.Equal(t, "message bus not initialized to publish to final status queue", err.Error())
			},
			assertLogs: func(t *testing.T, logs []string) {
				require.Empty(t, logs)
			},
		},
		{
			name: "Bus Send gives error",
			req:  &datamanager.Notification{Id: "notif456", Status: datamanager.DeliveryStatus_PUBLISHED},
			setupMocks: func(service *Service, mockBus *mocks.MockMessageBus) {
				mockBus.On("Send", mock.Anything, "final_status_notification", mock.Anything, mock.Anything).
					Return("", fmt.Errorf("queue error")).Once()
				service.Bus = mockBus
			},
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.Error(t, err)
				require.Equal(t, "failed to send message to queue final_status_notification: queue error", err.Error())
			},
			assertLogs: func(t *testing.T, logs []string) {
				require.Contains(t, logs, "Publishing final status of notification")
			},
		},
		{
			name: "No error (successful message publish)",
			req:  &datamanager.Notification{Id: "notif789", Status: datamanager.DeliveryStatus_PUBLISHED},
			setupMocks: func(service *Service, mockBus *mocks.MockMessageBus) {
				mockBus.On("Send", mock.Anything, "final_status_notification", mock.Anything, mock.Anything).
					Return("message-id-123", nil).Once()
				service.Bus = mockBus
			},
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.NoError(t, err)
			},
			assertLogs: func(t *testing.T, logs []string) {
				require.Contains(t, logs, "Publishing final status of notification")
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			mockBus := new(mocks.MockMessageBus)
			mockLogger := &mocks.MockLogger{}

			service := &Service{
				FinalStatusQueue: "final_status_notification",
				Logger:           mockLogger,
				Bus:              mockBus,
			}

			if tc.setupMocks != nil {
				tc.setupMocks(service, mockBus)
			}

			err := service.PublishToFinalStatusQueue(context.Background(), tc.req, mockLogger)

			tc.wantErr(t, err)

			if tc.assertLogs != nil {
				logs := mockLogger.GetLogs()
				tc.assertLogs(t, logs)
			}

			mockBus.AssertExpectations(t)
		})
	}
}
