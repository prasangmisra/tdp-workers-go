package consumer

import (
	"fmt"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/app/config"
	"github.com/tucowsinc/tdp-shared-go/logger"
)

const (
	SERVICE_NAME = "webhook_sender"
)

func New(cfg *config.Config, log logger.ILogger) (mb messagebus.MessageBus, err error) {
	// Create RabbitMQ options
	optsBuilder := messagebus.NewRabbitMQOptionsBuilder().
		WithExchange(cfg.RMQ.Exchange).
		WithExKind(cfg.RMQ.ExchangeKind).
		WithExDurable(cfg.RMQ.ExchangeDurable).
		WithQType(cfg.RMQ.QueueType)

	opts, err := optsBuilder.Build()
	if err != nil {
		return nil, fmt.Errorf("failed to build message bus options: %w", err)
	}

	mbOpts := messagebus.MessageBusOptions{
		CertFile:   cfg.RMQ.CertFile,
		KeyFile:    cfg.RMQ.KeyFile,
		CACertFile: cfg.RMQ.CAFile,
		SkipVerify: cfg.RMQ.TLSSkipVerify,
		ServerName: cfg.RMQ.VerifyServerName,
		Rmq:        *opts,
		Log:        log,
	}

	// **Create Message Bus & Declare the Webhook Notification Queue**
	mb, err = messagebus.New(cfg.RMQurl(), SERVICE_NAME, cfg.RMQ.Readers, &mbOpts) // Queue name not needed here
	if err != nil {
		return nil, fmt.Errorf("failed to create message bus instance: %w", err)
	}
	retryQueues := make([]string, len(cfg.RMQ.RetryQueues))
	for i, queue := range cfg.RMQ.RetryQueues {
		retryQueues[i] = queue.Name
		if err := mb.DeclareQueue(queue.Name,
			messagebus.WithDLExchange(cfg.RMQ.NotificationwebhookDLExchange)); err != nil {
			return nil, fmt.Errorf("failed to declare retry queue %s: %w", queue.Name, err)
		}
	}
	if err := mb.DeclareQueue(
		cfg.RMQ.WebhookSendQueue.Name,
		messagebus.WithExchange(cfg.RMQ.Exchange, cfg.RMQ.WebhookSendQueue.Name),
		messagebus.WithExchange(cfg.RMQ.NotificationwebhookDLExchange, retryQueues...),
		messagebus.WithMaxPriority(cfg.RMQ.WebhookSendQueue.MaxPriority),
	); err != nil {
		return nil, fmt.Errorf("failed to declare main webhook queue: %w", err)
	}

	return mb, nil
}
