package sqs

import (
	"context"
	"sync"
	"testing"

	"github.com/aws/aws-sdk-go-v2/service/sqs"
	sqstypes "github.com/aws/aws-sdk-go-v2/service/sqs/types"
	"github.com/google/uuid"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	config "github.com/tucowsinc/tdp-workers-go/pkg/config"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	hostingproto "github.com/tucowsinc/tucows-domainshosting-app/cmd/functions/order/proto"
	"google.golang.org/protobuf/proto"
)

type SQSConsumerTestSuite struct {
	suite.Suite
	ctx           context.Context
	options       *SqsOptions
	mockSQSClient *MockSQSClientAPI
	sqsConsumer   Consumer
}

func TestSQSConsumerSuite(t *testing.T) {
	suite.Run(t, new(SQSConsumerTestSuite))
}

func (s *SQSConsumerTestSuite) SetupSuite() {
	s.ctx = context.Background()

	config, err := config.LoadConfiguration("../../.env")
	s.NoError(err, "Failed to read config from .env")

	config.LogLevel = "mute" // suppress log output
	log.Setup(config)
}

func (s *SQSConsumerTestSuite) SetupTest() {
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

	s.sqsConsumer, err = NewConsumer(s.ctx, *options)

	s.NoErrorf(err, "failed to instantiate sqs publisher")
}

func (s *SQSConsumerTestSuite) TearDownTest() {
	// can be used for post test cleanup actions
}

func (s *SQSConsumerTestSuite) TestNewConsumer__Failure() {
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

	sqsConsumer, err := NewConsumer(s.ctx, *options)

	s.ErrorIs(err, expErr)
	s.Nil(sqsConsumer)

	mockSQSClient.AssertExpectations(s.T())
}

func (s *SQSConsumerTestSuite) TestConsumer__Success() {
	testMessageId := uuid.NewString()
	testMsgHandle := uuid.NewString()
	expStatus := "test-status"
	expMessage := &hostingproto.OrderDetailsResponse{Id: uuid.NewString(), Status: expStatus}

	expRawMsg, _ := proto.Marshal(expMessage)

	mockSQSClient := &MockSQSClientAPI{}
	testQueue := "test-queue"

	options, err := NewOptionsBuilder().
		WithQueueName(testQueue).
		WithAccessKeyId("test-access-key").
		WithSecretAccessKey("test-secret-key").
		WithSQSClientAPI(mockSQSClient).
		Build()

	s.NoError(err)

	mockSQSClient.On("GetQueueUrl", mock.Anything, mock.Anything, mock.Anything).Return(
		&sqs.GetQueueUrlOutput{QueueUrl: &testQueue},
		nil,
	)

	ctx, ctxCancel := context.WithCancel(s.ctx)
	defer ctxCancel()

	sqsConsumer, err := NewConsumer(ctx, *options)

	s.NoError(err)

	mockSQSClient.On("ReceiveMessage", mock.Anything, mock.Anything, mock.Anything).Return(
		&sqs.ReceiveMessageOutput{
			Messages: []sqstypes.Message{{
				MessageId:     &testMessageId,
				ReceiptHandle: &testMsgHandle,
				MessageAttributes: map[string]sqstypes.MessageAttributeValue{
					"body": {BinaryValue: expRawMsg},
				},
			}},
		},
		nil,
	).Once()

	// simulate no more messages after first received
	mockSQSClient.On("ReceiveMessage", mock.Anything, mock.Anything, mock.Anything).Return(
		&sqs.ReceiveMessageOutput{
			Messages: []sqstypes.Message{},
		},
		nil,
	)

	mockSQSClient.On("DeleteMessage", mock.Anything, &sqs.DeleteMessageInput{
		QueueUrl:      &testQueue,
		ReceiptHandle: &testMsgHandle,
	}, mock.Anything).Return(nil, nil)

	wg := sync.WaitGroup{}

	var receivedMessage *hostingproto.OrderDetailsResponse
	var receivedServer Server
	handler := func(server Server, message proto.Message) (err error) {
		defer wg.Done()

		receivedMessage = message.(*hostingproto.OrderDetailsResponse)
		receivedServer = server

		return
	}

	sqsConsumer.Register(&hostingproto.OrderDetailsResponse{}, handler)

	wg.Add(1)
	go sqsConsumer.Consume()
	wg.Wait()

	s.Equal(expMessage.GetStatus(), receivedMessage.GetStatus())

	s.Equal(testMessageId, receivedServer.Envelope.GetId())

	mockSQSClient.AssertExpectations(s.T())
}

func (s *SQSConsumerTestSuite) Test_deleteMessage__Failure() {
	testHandle := uuid.NewString()
	mockSQSClient := &MockSQSClientAPI{}
	testQueue := "test-queue"

	options, err := NewOptionsBuilder().
		WithQueueName(testQueue).
		WithAccessKeyId("test-access-key").
		WithSecretAccessKey("test-secret-key").
		WithSQSClientAPI(mockSQSClient).
		Build()

	s.NoError(err)

	sqsConsumer := sqsConsumer{
		ctx:      s.ctx,
		client:   mockSQSClient,
		options:  options,
		queueUrl: &testQueue,
	}

	testCases := []struct {
		testHandle  *string
		setUpFunc   func()
		expErrorMsg string
	}{{
		testHandle:  nil,
		setUpFunc:   func() {},
		expErrorMsg: "cannot delete message handle is nil",
	}, {
		testHandle: &testHandle,
		setUpFunc: func() {
			mockSQSClient.On("DeleteMessage", mock.Anything, &sqs.DeleteMessageInput{
				QueueUrl:      &testQueue,
				ReceiptHandle: &testHandle,
			}, mock.Anything).Return(nil, errors.New("error deleting message handle"))
		},
		expErrorMsg: "error deleting message handle",
	}}

	for _, tt := range testCases {
		tt.setUpFunc()

		err = sqsConsumer.deleteMessage(tt.testHandle)

		s.ErrorContains(err, tt.expErrorMsg)
	}

}
