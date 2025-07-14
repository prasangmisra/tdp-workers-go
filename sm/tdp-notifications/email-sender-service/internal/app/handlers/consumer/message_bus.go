package consumer

import (
	"fmt"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-notifications/email-sender-service/internal/app/config"
	"github.com/tucowsinc/tdp-shared-go/logger"
)

const (
	SERVICE_NAME = "email_sending_service"
)

func New(cfg *config.Config, log logger.ILogger) (messagebus.MessageBus, error) {
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

	mb, err := messagebus.New(cfg.RMQurl(), SERVICE_NAME, cfg.RMQ.Readers, &mbOpts) // Queue name not needed here
	if err != nil {
		return nil, fmt.Errorf("failed to create message bus instance: %w", err)
	}

	return mb, nil
}
