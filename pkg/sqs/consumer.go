package sqs

import (
	"context"
	"fmt"
	"time"

	"google.golang.org/protobuf/proto"

	"github.com/aws/aws-sdk-go-v2/service/sqs"
	sqstypes "github.com/aws/aws-sdk-go-v2/service/sqs/types"
	"github.com/pkg/errors"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/gensyncmap"
	wire "github.com/tucowsinc/tdp-messagebus-go/pkg/message"
	"github.com/tucowsinc/tdp-messages-go/message"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
	hostingproto "github.com/tucowsinc/tucows-domainshosting-app/cmd/functions/order/proto"
)

const BufferSize = 100

var ackMap = gensyncmap.New[string, string]()
var _ Consumer = (*sqsConsumer)(nil)

type Consumer interface {
	Ping(ctx context.Context) error
	Consume()
	Register(m proto.Message, h HandlerFuncType)
}

// NewConsumer creates a new instance of SqsConsumer used to consume SQS messages
func NewConsumer(ctx context.Context, options SqsOptions) (c Consumer, err error) {

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

	consumer := &sqsConsumer{
		ctx:      ctx,
		client:   client,
		queueUrl: queueUrl.QueueUrl,
		options:  &options,
	}

	consumer.handlers = make(map[string]handlerType)
	consumer.sqsMessages = make(chan sqstypes.Message, BufferSize)
	consumer.wireMessages = make(chan *message.TcWire, BufferSize)

	return consumer, err
}

// Ping checks if the SQS queue is accessible
func (c *sqsConsumer) Ping(ctx context.Context) error {
	_, err := c.client.GetQueueUrl(ctx, &sqs.GetQueueUrlInput{
		QueueName:              &c.options.QueueName,
		QueueOwnerAWSAccountId: &c.options.QueueAccountId,
	})

	return err
}

// Register create a mapping between message type to a message handler
func (c *sqsConsumer) Register(m proto.Message, h HandlerFuncType) {
	msgType := string(m.ProtoReflect().Descriptor().FullName())

	c.handlers[msgType] = handlerType{
		Handler:     h,
		messageType: m,
	}
}

// Consume starts a loop to consume messages from SQS
func (c *sqsConsumer) Consume() {
	for i := 0; i < c.options.NumReceivers; i++ {
		go c.receive()
	}

	for {
		output, err := c.client.ReceiveMessage(c.ctx, &sqs.ReceiveMessageInput{
			QueueUrl:              c.queueUrl,
			MaxNumberOfMessages:   10,
			VisibilityTimeout:     30, // messages are redelivered after 30 second if not deleted
			MessageAttributeNames: []string{string(sqstypes.QueueAttributeNameAll)},
			AttributeNames:        []sqstypes.QueueAttributeName{sqstypes.QueueAttributeName(sqstypes.MessageSystemAttributeNameSentTimestamp)},
		})

		if c.ctx.Err() != nil {
			log.Debug("context done closing consumer loop...")
			return
		}

		if err != nil {
			log.Error("error receiving messages", log.Fields{
				types.LogFieldKeys.Error: err.Error(),
			})
			continue
		}

		if len(output.Messages) == 0 {
			log.Debug("no new messages; sleeping...")
			time.Sleep(5 * time.Second)
			continue
		}

		for _, msg := range output.Messages {
			c.sqsMessages <- msg
		}

	}
}

// ack provides a mechanism to ack a message on SQS that has been processed by the consumer
func (c *sqsConsumer) ack(id string) {
	msgHandle, ok := ackMap.Get(id)
	if !ok {
		log.Error("cannot find message in to-be acked list", log.Fields{"id": id})
		return
	}

	err := c.deleteMessage(msgHandle)
	if err != nil {
		log.Error("error acking message", log.Fields{
			"id":                     id,
			types.LogFieldKeys.Error: err.Error(),
		})
	}

	log.Debug("message deleted", log.Fields{"id": id})

	ackMap.Del(id)
}

func (c *sqsConsumer) deleteMessage(msgHandle *string) (err error) {
	if msgHandle == nil {
		return errors.New("cannot delete message handle is nil")
	}

	_, err = c.client.DeleteMessage(c.ctx, &sqs.DeleteMessageInput{
		QueueUrl:      c.queueUrl,
		ReceiptHandle: msgHandle,
	})
	if err != nil {
		log.Error("error deleting message handle", log.Fields{
			"msg_handle":             *msgHandle,
			types.LogFieldKeys.Error: err.Error(),
		})
	}

	return
}

func (c *sqsConsumer) receive() {
	for {
		select {
		case sqsMsg := <-c.sqsMessages:
			c.decode(&sqsMsg)
		case wireMsg := <-c.wireMessages:
			c.handle(wireMsg)
		case <-c.ctx.Done():
			log.Debug("sqs receiver: got termination signal")
			return
		}
	}
}

func (c *sqsConsumer) decode(sqsMsg *sqstypes.Message) {

	payload, ok := sqsMsg.MessageAttributes["body"]
	if !ok {
		log.Error("message does not contain 'body' attribute", log.Fields{"message_id": *sqsMsg.MessageId})
		return
	}

	log.Debug("message received", log.Fields{"message_id": *sqsMsg.MessageId})

	decoded := payload.BinaryValue

	// wireMsg, err := wire.FromBytes(decoded)
	// if err != nil {
	// 	log.Error("error decoding payload", log.Fields{
	// 		"message_id":             *sqsMsg.MessageId,
	// 		types.LogFieldKeys.Error: err.Error(),
	// 	})
	// 	return
	// }

	// simulating TcWire received
	msg := new(hostingproto.OrderDetailsResponse)
	err := proto.Unmarshal(decoded, msg)
	if err != nil {
		log.Error("error decoding payload", log.Fields{
			"message_id":             *sqsMsg.MessageId,
			types.LogFieldKeys.Error: err.Error(),
		})
		return
	}

	wireMsg, err := wire.New("hosting", msg, "", "")
	if err != nil {
		return
	}

	wireMsg.Id = *sqsMsg.MessageId

	msgId := wireMsg.GetId()
	// if msgId == "" {
	// 	log.Debug("invalid message format; deleting message", log.Fields{"message_id": *sqsMsg.MessageId})
	// 	c.deleteMessage(sqsMsg.ReceiptHandle)
	// 	return
	// }

	ackMap.Set(msgId, sqsMsg.ReceiptHandle)
	c.wireMessages <- wireMsg
}

func (c *sqsConsumer) handle(wireMsg *message.TcWire) {

	msgId := wireMsg.GetId()
	msgType := wireMsg.MessageType

	handler, ok := c.handlers[msgType]
	if !ok {
		log.Warn("no handler function is provided for message type. ignoring...", log.Fields{"message_type": msgType})
		return
	}

	headers, err := wire.DecodeHeaders(wireMsg.GetHeaders())
	if err != nil {
		log.Error("error decoding message headers", log.Fields{
			"message_id":             msgId,
			types.LogFieldKeys.Error: err.Error(),
		})
		return
	}

	server := Server{
		Ctx:      c.ctx,
		Envelope: wireMsg,
		Headers:  headers,
	}

	msg, err := wire.DecodePayload(wireMsg.GetPayload())
	if err != nil {
		log.Error("error decoding message payload", log.Fields{
			"message_id":             msgId,
			types.LogFieldKeys.Error: err.Error(),
		})
		return
	}

	// panic recovery to gracefully handle user defined handler functions
	defer func() {
		if r := recover(); r != nil {
			log.Error("call to handler was not successful: panic", log.Fields{
				"message_type":           msgType,
				types.LogFieldKeys.Error: err.Error(),
			})
			err = errors.New(fmt.Sprintf("panic while handling message: %v", r))
		}
	}()

	// calling user defined handler for given message type
	err = handler.Handler(server, msg)
	if err != nil {
		log.Error("call to handler was not successful", log.Fields{
			"message_type":           msgType,
			types.LogFieldKeys.Error: err.Error(),
		})
	} else {
		// delete message if successfully processed
		c.ack(msgId)
	}
}
