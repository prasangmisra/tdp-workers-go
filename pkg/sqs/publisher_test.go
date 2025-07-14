package sqs

import (
	"context"
	"testing"

	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/google/uuid"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	messages "github.com/tucowsinc/tdp-messages-go/message/common"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"

	"github.com/tucowsinc/tdp-workers-go/pkg/config"
)

type SQSPublisherTestSuite struct {
	suite.Suite
	ctx           context.Context
	mockSQSClient *MockSQSClientAPI
	sqsPublisher  Publisher
	options       *SqsOptions
}

func TestSQSPublisherSuite(t *testing.T) {
	suite.Run(t, new(SQSPublisherTestSuite))
}

func (s *SQSPublisherTestSuite) SetupSuite() {
	s.ctx = context.Background()

	cfg := config.Config{}
	cfg.LogLevel = "mute"
	cfg.LogOutputSink = "stdout"
	cfg.LogEnvironment = "dev"

	log.Setup(cfg)
}

func (s *SQSPublisherTestSuite) SetupTest() {
	mockSQSClient := &MockSQSClientAPI{}
	testQueue := "test-queue"

	options, err := NewOptionsBuilder().
		WithQueueName(testQueue).
		WithSQSClientAPI(mockSQSClient).
		WithAccessKeyId("test-access-id").
		WithSecretAccessKey("test-secret-key").
		Build()

	s.options = options

	s.NoErrorf(err, "failed to build sqs consumer options")

	s.mockSQSClient = mockSQSClient

	s.mockSQSClient.On("GetQueueUrl", mock.Anything, mock.Anything, mock.Anything).Return(
		&sqs.GetQueueUrlOutput{QueueUrl: &testQueue},
		nil,
	)

	s.sqsPublisher, err = NewPublisher(s.ctx, *options)

	s.NoErrorf(err, "failed to instantiate sqs publisher")
}

func (s *SQSPublisherTestSuite) TearDownTest() {
	// can be used for post test cleanup actions
}

func (s *SQSPublisherTestSuite) TestNewPublisher__Failure() {
	expErr := errors.New("failed get queue url")

	mockSQSClient := &MockSQSClientAPI{}
	mockSQSClient.On("GetQueueUrl", mock.Anything, mock.Anything, mock.Anything).Return(
		nil,
		expErr,
	)

	options, err := NewOptionsBuilder().
		WithQueueName("test-queue").
		WithAccessKeyId("test-access-key").
		WithSecretAccessKey("test-secret-key").
		WithSQSClientAPI(mockSQSClient).
		Build()

	s.NoError(err)

	sqsPublisher, err := NewPublisher(s.ctx, *options)

	s.ErrorIs(err, expErr)
	s.Nil(sqsPublisher)

	mockSQSClient.AssertExpectations(s.T())
}

func (s *SQSPublisherTestSuite) TestSend__Success() {
	testMessage := &messages.Money{CurrencyCode: "CAD", Units: 100}

	expMsgId := uuid.NewString()

	mockSQSClient := &MockSQSClientAPI{}
	testQueue := "test-queue"

	mockSQSClient.On("GetQueueUrl", mock.Anything, mock.Anything, mock.Anything).Return(
		&sqs.GetQueueUrlOutput{QueueUrl: &testQueue},
		nil,
	)

	s.mockSQSClient.On("SendMessage", mock.Anything, mock.Anything, mock.Anything).Return(
		&sqs.SendMessageOutput{
			MessageId: &expMsgId,
		},
		nil,
	)

	msgId, err := s.sqsPublisher.Send(testMessage)

	s.NoError(err)
	s.Equal(msgId, expMsgId)

	s.mockSQSClient.AssertExpectations(s.T())
}

func (s *SQSPublisherTestSuite) TestSend__FailedSendMessage() {
	testMessage := &messages.Money{CurrencyCode: "CAD", Units: 100}

	expErr := errors.New("failed to send message")

	s.mockSQSClient.On("GetQueueUrl", mock.Anything, mock.Anything, mock.Anything).Return(
		&sqs.GetQueueUrlOutput{QueueUrl: &s.options.QueueName},
		nil,
	)

	s.mockSQSClient.On("SendMessage", mock.Anything, mock.Anything, mock.Anything).Return(
		nil,
		expErr,
	)

	msgId, err := s.sqsPublisher.Send(testMessage)

	s.ErrorIs(err, expErr)
	s.Empty(msgId)

	s.mockSQSClient.AssertExpectations(s.T())
}
