package main

import (
	"context"
	"time"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-shared-go/healthcheck"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"

	"github.com/tucowsinc/tdp-workers-go/certificate_updater/handlers"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	message_bus "github.com/tucowsinc/tdp-workers-go/pkg/message_bus"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

func main() {
	// get config
	cfg, err := config.LoadConfiguration(".env")

	// setup logging
	log.Setup(cfg)
	defer log.Sync()

	if err != nil {
		log.Fatal(types.LogMessages.ConfigurationLoadFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}

	log.Info(types.LogMessages.ConfigurationLoaded)

	tracer, otelShutdown, err := tracing.Setup(context.Background(), cfg)
	if err != nil {
		log.Fatal("Error setting up tracing", log.Fields{"error": err})
	}
	defer func() {
		err = oteltrace.JoinErrors(err, otelShutdown(context.Background()))
		log.Error("error is: ", log.Fields{"error": err})
	}()

	// setup messagebus
	messageBusServer, err := message_bus.SetupMessageBus(cfg)

	if err != nil {
		log.Fatal(types.LogMessages.MessageBusSetupFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}
	defer messageBusServer.Finalize()

	db, err := database.New(cfg.PostgresPoolConfig(), cfg.GetDBLogLevel())
	if err != nil {
		log.Fatal(types.LogMessages.DatabaseConnectionFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}
	defer db.Close()

	service := handlers.NewWorkerService(messageBusServer, db, tracer)
	service.RegisterHandlers()

	if cfg.HealthcheckEnabled {
		healthCheckServer := healthcheck.New(cfg.HealthcheckPort)

		for _, check := range service.HealthChecks(cfg) {
			healthCheckServer.RegisterHealthCheck(
				check,
				healthcheck.WithFrequency(time.Duration(cfg.HealthcheckInterval)*time.Second),
				healthcheck.WithTimeout(time.Duration(cfg.HealthcheckTimeout)*time.Second),
			)
		}

		go func() {
			log.Info("Starting health check server for certificate provision updater worker")
			err = healthCheckServer.Start(context.Background())
			if err != nil {
				log.Fatal("Error occurred while starting health check server for certificate provision updater worker", log.Fields{"error": err})
			}
		}()
	}

	queues := []string{cfg.RmqQueueName}
	log.Info(types.LogMessages.ConsumingQueuesStarted, log.Fields{
		types.LogFieldKeys.Queue: queues,
	})

	consumerOptions := &messagebus.ConsumerOptions{
		Prefetch: &cfg.RmqPrefetchCount,
	}

	if err = messageBusServer.Consume(queues, consumerOptions); err != nil {
		log.Fatal(types.LogMessages.ConsumingQueuesFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}

	log.Info(types.LogMessages.WorkerTerminated)
}
