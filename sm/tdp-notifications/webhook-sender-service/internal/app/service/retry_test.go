package service

import (
	"context"
	"fmt"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/app/config"
	mocks "github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/app/mock"
)

// Test GetNextRetryQueue
func TestGetNextRetryQueue(t *testing.T) {
	t.Parallel()
	service := &Service{
		Cfg: &config.Config{
			RMQ: config.RMQ{
				RetryQueues: []config.RetryQueue{
					{Name: "retry-queue-1", TTL: 60},
					{Name: "retry-queue-2", TTL: 120},
				},
			},
		},
	}

	tests := []struct {
		name       string
		retryCount int
		expected   string
		wantErr    bool
	}{
		{"Valid retry count", 0, "retry-queue-1", false},
		{"Valid retry count", 1, "retry-queue-2", false},
		{"Invalid retry count", 2, "", true},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			queue, err := service.GetNextRetryQueue(tc.retryCount)

			if tc.wantErr {
				require.Error(t, err)
				require.Contains(t, err.Error(), "no more retry queues available")
			} else {
				require.NoError(t, err)
				require.Equal(t, tc.expected, queue)
			}
		})
	}
}

// Test PublishToRetryQueue
func TestPublishToRetryQueue(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name       string
		req        *datamanager.Notification
		retryCount int
		setupMocks func(service *Service, mockBus *mocks.MockMessageBus)
		wantErr    require.ErrorAssertionFunc
		assertLogs func(t *testing.T, logs []string)
	}{
		{
			name:       "Bus is nil",
			req:        &datamanager.Notification{Id: "notif123"},
			retryCount: 1,
			setupMocks: func(service *Service, mockBus *mocks.MockMessageBus) {
				service.Bus = nil
			},
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.Error(t, err)
				require.Equal(t, "message bus not initialized to publish to retry queue", err.Error())
			},
			assertLogs: func(t *testing.T, logs []string) {
				require.Empty(t, logs)
			},
		},
		{
			name:       "Bus Send gives error",
			req:        &datamanager.Notification{Id: "notif456"},
			retryCount: 1,
			setupMocks: func(service *Service, mockBus *mocks.MockMessageBus) {
				mockBus.On("Send", mock.Anything, "retry-queue-2", mock.Anything, mock.Anything).
					Return("", fmt.Errorf("queue error")).Once()
				service.Bus = mockBus
			},
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.Error(t, err)
				require.Equal(t, "failed to send message to queue retry-queue-2: queue error", err.Error())
			},
			assertLogs: func(t *testing.T, logs []string) {
				require.Contains(t, logs, "Publishing message to queue")
				require.Contains(t, logs, "Message publishing to queue failed")
			},
		},
		{
			name:       "Successful publish to retry queue",
			req:        &datamanager.Notification{Id: "notif789"},
			retryCount: 0,
			setupMocks: func(service *Service, mockBus *mocks.MockMessageBus) {
				mockBus.On("Send", mock.Anything, "retry-queue-1", mock.Anything, mock.Anything).
					Return("message-id-123", nil).Once()
				service.Bus = mockBus
			},
			wantErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.NoError(t, err)
			},
			assertLogs: func(t *testing.T, logs []string) {
				require.Contains(t, logs, "Publishing message to queue")
				require.Contains(t, logs, "Message published to retry queue")
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
				Cfg: &config.Config{
					RMQ: config.RMQ{
						RetryQueues: []config.RetryQueue{{Name: "retry-queue-1", TTL: 60}, {Name: "retry-queue-2", TTL: 120}},
					},
				},
				Logger: mockLogger,
				Bus:    mockBus,
			}

			if tc.setupMocks != nil {
				tc.setupMocks(service, mockBus)
			}

			err := service.PublishToRetryQueue(context.Background(), service.Cfg.RMQ.RetryQueues[tc.retryCount].Name, tc.req, tc.retryCount, mockLogger)

			tc.wantErr(t, err)

			if tc.assertLogs != nil {
				logs := mockLogger.GetLogs()
				tc.assertLogs(t, logs)
			}

			mockBus.AssertExpectations(t)
		})
	}
}
