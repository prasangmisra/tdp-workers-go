package service

import (
	"context"
	"fmt"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/app/config"
	mocks "github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/app/mock"
	"github.com/tucowsinc/tdp-shared-go/logger"
)

type TestSuite struct {
	suite.Suite
	srvc           *Service
	cfg            *config.Config
	mockBus        *mocks.MockMessageBus
	mockLog        *logger.MockLogger
	mockHTTPClient *mocks.IHTTPClient
}

// Run the test suite
func TestServiceSuite(t *testing.T) {
	suite.Run(t, new(TestSuite))
}

// 🏗️ Runs ONCE before all tests
func (suite *TestSuite) SetupSuite() {
	cfg, err := config.LoadConfiguration("../../../configs")
	suite.Require().NoError(err)

	suite.cfg = &cfg
	suite.mockLog = &logger.MockLogger{}
	suite.mockBus = new(mocks.MockMessageBus)
	suite.mockHTTPClient = new(mocks.IHTTPClient)
	suite.srvc = New(&cfg, suite.mockLog, suite.mockBus, suite.mockHTTPClient) // ✅ Inject mock message bus
}

func (suite *TestSuite) TestGetNextRetryQueue() {
	assert := require.New(suite.T())

	testCases := []struct {
		name        string
		retryCount  int
		expected    string
		expectError bool
	}{
		{
			name:        "Valid Retry Queue - First Attempt",
			retryCount:  0,
			expected:    fmt.Sprintf("%s_retry_%d", suite.cfg.RMQ.WebhookSendQueue.Name, 1),
			expectError: false,
		},
		{
			name:        "Valid Retry Queue - Second Attempt",
			retryCount:  1,
			expected:    fmt.Sprintf("%s_retry_%d", suite.cfg.RMQ.WebhookSendQueue.Name, 2),
			expectError: false,
		},
		{
			name:        "Exceed Max Retries",
			retryCount:  len(suite.cfg.RMQ.RetryQueuesConfig.RetryIntervals),
			expected:    "",
			expectError: true,
		},
	}

	for _, tc := range testCases {
		suite.T().Run(tc.name, func(t *testing.T) {
			queue, err := suite.srvc.GetNextRetryQueue(tc.retryCount)

			if tc.expectError {
				assert.Error(err, "Expected an error for exceeding max retries")
			} else {
				assert.NoError(err, "Unexpected error for valid retry count")
				assert.Equal(tc.expected, queue, "Queue name should match expected value")
			}
		})
	}
}

// Test PublishToQueue functionality
func (suite *TestSuite) PublishToRetryQueue() {
	assert := require.New(suite.T())
	retryQueue := "retry-queue"
	notification := &datamanager.Notification{}
	retryCount := 1

	suite.mockBus.On("Send", mock.Anything, retryQueue, notification, mock.Anything).Return("msg-id", nil)

	err := suite.srvc.PublishToRetryQueue(context.Background(), retryQueue, notification, retryCount, &logger.MockLogger{})
	assert.NoError(err, "PublishToQueue should succeed")
	suite.mockBus.AssertCalled(suite.T(), "Send", mock.Anything, retryQueue, notification, mock.Anything)
}
