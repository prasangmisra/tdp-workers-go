package sqs

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/service/sqs"
)

// SQSClientAPI defines the interface for the sqs client functions
type SQSClientAPI interface {
	GetQueueUrl(ctx context.Context,
		input *sqs.GetQueueUrlInput,
		optFns ...func(*sqs.Options)) (*sqs.GetQueueUrlOutput, error)

	CreateQueue(ctx context.Context,
		input *sqs.CreateQueueInput,
		optFns ...func(*sqs.Options)) (*sqs.CreateQueueOutput, error)

	SendMessage(ctx context.Context,
		input *sqs.SendMessageInput,
		optFns ...func(*sqs.Options)) (*sqs.SendMessageOutput, error)

	ReceiveMessage(ctx context.Context,
		input *sqs.ReceiveMessageInput,
		optFns ...func(*sqs.Options)) (*sqs.ReceiveMessageOutput, error)

	DeleteMessage(ctx context.Context,
		input *sqs.DeleteMessageInput,
		optFns ...func(*sqs.Options)) (*sqs.DeleteMessageOutput, error)
}
