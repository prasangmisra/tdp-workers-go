package sqs

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/stretchr/testify/mock"
	"google.golang.org/protobuf/proto"
)

type MockSQSClientAPI struct {
	mock.Mock
}

func (m *MockSQSClientAPI) GetQueueUrl(ctx context.Context, input *sqs.GetQueueUrlInput, optFns ...func(*sqs.Options)) (output *sqs.GetQueueUrlOutput, err error) {
	args := m.Called(ctx, input, optFns)
	if args.Get(0) != nil {
		output = args.Get(0).(*sqs.GetQueueUrlOutput)
	}

	err = args.Error(1)
	return
}

func (m *MockSQSClientAPI) CreateQueue(ctx context.Context, input *sqs.CreateQueueInput, optFns ...func(*sqs.Options)) (output *sqs.CreateQueueOutput, err error) {
	args := m.Called(ctx, input, optFns)
	if args.Get(0) != nil {
		output = args.Get(0).(*sqs.CreateQueueOutput)
	}

	err = args.Error(1)
	return
}

func (m *MockSQSClientAPI) SendMessage(ctx context.Context, input *sqs.SendMessageInput, optFns ...func(*sqs.Options)) (output *sqs.SendMessageOutput, err error) {
	args := m.Called(ctx, input, optFns)
	if args.Get(0) != nil {
		output = args.Get(0).(*sqs.SendMessageOutput)
	}

	err = args.Error(1)
	return
}

func (m *MockSQSClientAPI) ReceiveMessage(ctx context.Context, input *sqs.ReceiveMessageInput, optFns ...func(*sqs.Options)) (output *sqs.ReceiveMessageOutput, err error) {
	args := m.Called(ctx, input, optFns)
	if args.Get(0) != nil {
		output = args.Get(0).(*sqs.ReceiveMessageOutput)
	}

	err = args.Error(1)
	return
}

func (m *MockSQSClientAPI) DeleteMessage(ctx context.Context, input *sqs.DeleteMessageInput, optFns ...func(*sqs.Options)) (output *sqs.DeleteMessageOutput, err error) {
	args := m.Called(ctx, input, optFns)
	if args.Get(0) != nil {
		output = args.Get(0).(*sqs.DeleteMessageOutput)
	}

	err = args.Error(1)
	return
}

type MockConsumer struct {
	mock.Mock
}

func (c *MockConsumer) Ping(ctx context.Context) error {
	args := c.Called(ctx)
	return args.Error(0)
}

func (c *MockConsumer) Consume() {
	c.Called()
}

func (c *MockConsumer) Register(m proto.Message, h HandlerFuncType) {
	c.Called(m, h)
}
