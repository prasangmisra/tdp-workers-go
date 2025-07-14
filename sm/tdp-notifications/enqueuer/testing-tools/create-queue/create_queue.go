// Creates the queue for the enqueuer service
// Ordinarily, this would be created by the WebhookSender as a part of its setup but this tool allows us to create the queue without it
// Queue name is taken from the config file

package main

import (
	"fmt"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-notifications/enqueuer/internal/config"
	logging "github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/logger/zap"
)

const configPath = "configs"

func main() {

	cfg, err := config.LoadConfiguration(configPath)
	logger := zap.NewTdpLogger(cfg.Log) // Log config is loaded by default values anyway
	if err != nil {
		logger.Fatal("failed to load tdp-notifications notification-manager-service configuration", logging.Fields{"error": err})
	}

	logger.Info("configuration successfully loaded, starting tdp-notifications notification-manager-service...")

	//Get a connection to the bus
	opts, err := messagebus.NewRabbitMQOptionsBuilder().
		WithExchange(cfg.RMQ.Exchange).
		WithQType(cfg.RMQ.QueueType).
		Build()
	if err != nil {
		logger.Fatal("failed to build message bus options", logging.Fields{"error": err})
	}
	mbOpts := messagebus.MessageBusOptions{
		CertFile:   cfg.RMQ.CertFile,
		KeyFile:    cfg.RMQ.KeyFile,
		CACertFile: cfg.RMQ.CAFile,
		SkipVerify: cfg.RMQ.TLSSkipVerify,
		ServerName: cfg.RMQ.VerifyServerName,

		Rmq: *opts,
		Log: logger,
	}
	mBus, err := messagebus.New(cfg.RMQurl(), "notification-enqueuer", cfg.RMQ.Readers, &mbOpts)
	if err != nil {
		logger.Fatal("failed to create message bus instance", logging.Fields{"error": err})
	}

	if err := mBus.DeclareQueue(
		cfg.RMQ.WebhookQueue.QueueName,
		messagebus.WithExchange(cfg.RMQ.Exchange, cfg.RMQ.WebhookQueue.QueueName),
	); err != nil {
		fmt.Print("failed to declare main webhook queue: %w", err)
	}
}
