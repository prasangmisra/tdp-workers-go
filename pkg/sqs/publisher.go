package sqs

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	sqstypes "github.com/aws/aws-sdk-go-v2/service/sqs/types"
	"github.com/google/uuid"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
	"google.golang.org/protobuf/proto"
)

var _ Publisher = (*sqsPublisher)(nil)

type Publisher interface {
	Send(msg proto.Message) (msgId string, err error)
}

// NewPublisher provided a new instance of SqsPublisher used to send messages to SQS
func NewPublisher(ctx context.Context, options SqsOptions) (Publisher, error) {

	client := options.ClientAPI
	if client == nil {
		cfg, err := options.LoadConfiguration(ctx)
		if err != nil {
			log.Error("error loading aws configuration", log.Fields{
				types.LogFieldKeys.Error: err.Error(),
			})
			return nil, err
		}

		client = sqs.NewFromConfig(cfg)
	}

	queueUrl, err := client.GetQueueUrl(ctx, &sqs.GetQueueUrlInput{
		QueueName:              &options.QueueName,
		QueueOwnerAWSAccountId: &options.QueueAccountId,
	})

	if err != nil {
		log.Error("error getting queue url for queue", log.Fields{
			types.LogFieldKeys.Queue: options.QueueName,
			types.LogFieldKeys.Error: err.Error(),
		})
		return nil, err
	}

	log.Info("AWS queue URL", log.Fields{"url": *queueUrl.QueueUrl})

	publisher := &sqsPublisher{
		ctx:      ctx,
		client:   client,
		queueUrl: queueUrl.QueueUrl,
		options:  &options,
	}

	return publisher, nil
}

// Send sends a message to SQS to the provided queue name. It returns the message id returned by SQS
func (p *sqsPublisher) Send(msg proto.Message) (msgId string, err error) {

	var emptyBody = " "

	// wireMsg, err := wire.New("sqs-publisher", msg, "", "")
	// if err != nil {
	// 	log.Errorf("Error creating wire message: %v", log.Fields{
	// 		types.LogFieldKeys.Error: err.Error(),
	// 	})
	// 	return
	// }

	rawMsg, _ := proto.Marshal(msg)
	payload := sqstypes.MessageAttributeValue{
		DataType:    aws.String("Binary"),
		BinaryValue: rawMsg,
	}

	messageGroupId := "test-message-group-id"
	messageDeduplicationId := uuid.NewString()
	output, err := p.client.SendMessage(p.ctx, &sqs.SendMessageInput{
		DelaySeconds:           0,
		QueueUrl:               p.queueUrl,
		MessageBody:            &emptyBody,
		MessageGroupId:         &messageGroupId,
		MessageDeduplicationId: &messageDeduplicationId,
		MessageAttributes: map[string]sqstypes.MessageAttributeValue{
			"body": payload,
		},
	})

	if err != nil {
		log.Error("Error sending message to queue", log.Fields{
			types.LogFieldKeys.Queue: *p.queueUrl,
			types.LogFieldKeys.Error: err.Error()})
		return "", err
	}

	return *output.MessageId, nil
}
