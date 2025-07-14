package main

import (
	"context"
	"fmt"
	"time"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"

	"github.com/tucowsinc/tdp-shared-go/healthcheck"

	"github.com/tucowsinc/tdp-workers-go/contact/handlers"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	message_bus "github.com/tucowsinc/tdp-workers-go/pkg/message_bus"
)

func main() {

	cfg, err := config.LoadConfiguration(".env")
	if err != nil {
		panic(fmt.Errorf("error loading configuration: %v", err))
	}
	log.Setup(cfg)
	defer log.Sync()

	log.Info("Starting contact provision worker")

	log.Info(types.LogMessages.ConfigurationLoaded)

	tracer, otelShutdown, err := tracing.Setup(context.Background(), cfg)
	if err != nil {
		log.Fatal("Error setting up tracing", log.Fields{"error": err})
	}
	defer func() {
		err = oteltrace.JoinErrors(err, otelShutdown(context.Background()))
		log.Error("error is: ", log.Fields{"error": err})
	}()

	// Instantiate a messagebus
	messagebusServer, err := message_bus.SetupMessageBus(cfg)
	if err != nil {
		log.Fatal(types.LogMessages.MessageBusSetupFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}
	defer messagebusServer.Finalize()

	db, err := database.New(cfg.PostgresPoolConfig(), cfg.GetDBLogLevel())

	if err != nil {
		log.Fatal(types.LogMessages.DatabaseConnectionFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}
	defer db.Close()

	service := handlers.NewWorkerService(messagebusServer, db, tracer)
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
			log.Info("Starting health check server for contact provision worker")
			err = healthCheckServer.Start(context.Background())
			if err != nil {
				log.Fatal("Error occurred while starting health check server for contact provision worker", log.Fields{"error": err})
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

	err = messagebusServer.Consume(queues, consumerOptions) // block until the messagebus quits
	if err != nil {
		log.Fatal(types.LogMessages.ConsumingQueuesFailed, log.Fields{types.LogFieldKeys.Error: err})
	}

	log.Info(types.LogMessages.WorkerTerminated)
}
