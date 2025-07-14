package main

// This class is the main entry point for the enqueuer application.
// It is essentially a wrapper for a call to the enqueuer class
// When executed, it will
//  -  scan the database for notifications (see "select_string")
//  -  extract and then put the notification info onto the message bus (see "targetQueue")
//  -  update each notification status in the database to "publishing"

// It is expected that this process will be run on a cron job (e.g. every 30 seconds or so)

import (
	"context"
	"fmt"
	"sync"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-notifications/enqueuer/internal/config"
	"github.com/tucowsinc/tdp-notifications/enqueuer/internal/database/model"
	enq "github.com/tucowsinc/tdp-notifications/enqueuer/internal/enqueuer"
	"github.com/tucowsinc/tdp-notifications/enqueuer/internal/types"
	logging "github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/logger/zap"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
)

// select_string is the query to fetch notifications from the database
const selectStringWebhook = "SELECT vn.* FROM notification_delivery nd JOIN v_notification vn ON vn.id = nd.id WHERE vn.status = 'received' and vn.channel_type='webhook' order by created_date asc LIMIT 100"
const selectStringEmail = "SELECT vn.* FROM notification_delivery nd JOIN v_notification vn ON vn.id = nd.id WHERE vn.status = 'received' and vn.channel_type='email' order by created_date asc LIMIT 100"
const configPath = "configs"

func main() {

	// Load the config
	config, err := config.LoadConfiguration(configPath)
	logger := zap.NewTdpLogger(config.Log)
	if err != nil {
		logger.Fatal("failed to load configuration", logging.Fields{"error": err})
	}

	// Execute the run function
	if err := run(&config, logger); err != nil {
		logger.Fatal("error running service", logging.Fields{"error": err})
	}
}

func run(cfg *config.Config, logger logging.ILogger) error {
	// Get a connection to the database
	db, err := database.New(cfg.SubscriptionDB.PostgresPoolConfig(), logger)
	if err != nil {
		logger.Fatal("failed to create database connection", logging.Fields{"error": err})
	}

	// Get a connection to the message bus
	mb, err := getMessageBus(cfg, logger)
	if err != nil {
		logger.Fatal("failed to create message bus", logging.Fields{"error": err})
	}
	defer mb.Dispose()

	// Create an instance of an EnqueuerConfig.  This holds the basic configuration for the enqueuer
	webhookCfg, err := enq.NewDbEnqueuerConfigBuilder[*model.VNotification]().
		WithRawSelect(selectStringWebhook).
		WithUpdateFieldValueMap(map[string]interface{}{"status": "publishing"}).
		WithQueue(cfg.RMQ.WebhookQueue.QueueName).
		Build()
	if err != nil {
		logger.Fatal("failed to build webhook enqueuer config", logging.Fields{"error": err})
	}

	emailCfg, err := enq.NewDbEnqueuerConfigBuilder[*model.VNotification]().
		WithRawSelect(selectStringEmail).
		WithUpdateFieldValueMap(map[string]interface{}{"status": "publishing"}).
		WithQueue(cfg.RMQ.EmailQueue.QueueName).
		Build()
	if err != nil {
		logger.Fatal("failed to build email enqueuer config", logging.Fields{"error": err})
	}

	// Create an instance of the enqueuer
	webhookEnqueuer := enq.DbMessageEnqueuer[*model.VNotification]{
		Db:     db.GetDB(),
		Bus:    mb,
		Config: webhookCfg,
		Log:    logger,
	}

	emailEnqueuer := enq.DbMessageEnqueuer[*model.VNotification]{
		Db:     db.GetDB(),
		Bus:    mb,
		Config: emailCfg,
		Log:    logger,
	}
	ctx := context.Background()
	var wg sync.WaitGroup
	wg.Add(2)

	//GO!  Start the enqueuer
	logger.Info("starting enqueuers")
	go func() {
		defer wg.Done()
		if err := webhookEnqueuer.EnqueuerDbMessages(ctx, (*model.VNotification).ToWebhookProto); err != nil {
			logger.Error("webhook enqueuer failed", logging.Fields{"error": err})
		}
	}()

	go func() {
		defer wg.Done()
		if err := emailEnqueuer.EnqueuerDbMessages(ctx, (*model.VNotification).ToEmailProto); err != nil {
			logger.Error("email enqueuer failed", logging.Fields{"error": err})
		}
	}()

	wg.Wait()
	logger.Info("enqueuers finished")
	return nil
}

type bus struct {
	messagebus.MessageBus
}

func (b *bus) Dispose() {
	b.MessageBus.Finalize()
}

// Convenience method to return message bus instance
func getMessageBus(cfg *config.Config, logger logging.ILogger) (*bus, error) {

	// Create messagebus options
	opts, err := messagebus.NewRabbitMQOptionsBuilder().
		WithExchange(cfg.RMQ.Exchange).
		WithQType(cfg.RMQ.QueueType).
		Build()

	if err != nil {
		logger.Fatal("Error configuring rabbitmq options", logging.Fields{
			types.LogFieldKeys.Error: err,
		})
	}

	mbOpts := messagebus.MessageBusOptions{
		CertFile:   cfg.RMQ.CertFile,
		KeyFile:    cfg.RMQ.KeyFile,
		CACertFile: cfg.RMQ.CAFile,
		SkipVerify: cfg.RMQ.TLSSkipVerify,
		ServerName: cfg.RMQ.VerifyServerName,

		Rmq: *opts,
	}

	mBus, err := messagebus.New(cfg.RMQurl(), "enqueuer", cfg.RMQ.Readers, &mbOpts)

	if err != nil {
		return nil, fmt.Errorf("failed to create message bus instance: %w", err)
	}

	return &bus{MessageBus: mBus}, nil
}

// Dispose closes the connection to the RabbitMQ message bus.
// It calls the Finalize method on the messagebus.MessageBus which releases any resources associated with the message bus.
// This function should be called when the Bus is no longer needed.
