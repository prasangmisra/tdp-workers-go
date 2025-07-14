package main

import (
	"context"
	"fmt"
	"time"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-shared-go/healthcheck"

	"github.com/tucowsinc/tdp-workers-go/hosting/handlers"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/dns"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	message_bus "github.com/tucowsinc/tdp-workers-go/pkg/message_bus"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

func main() {
	cfg, err := config.LoadConfiguration(".env")
	if err != nil {
		panic(fmt.Errorf("error loading configuration: %v", err))
	}
	log.Setup(cfg)
	defer log.Sync()
	log.Info(types.LogMessages.ConfigurationLoaded)

	// Instantiate a message bus
	messageBusServer, err := message_bus.SetupMessageBus(cfg)
	if err != nil {
		log.Fatal(types.LogMessages.MessageBusSetupFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}

	db, err := database.New(cfg.PostgresPoolConfig(), cfg.GetDBLogLevel())
	if err != nil {
		log.Fatal(types.LogMessages.DatabaseConnectionFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}
	defer db.Close()

	resolver, err := dns.NewDNSResolver(cfg)
	if err != nil {
		log.Fatal("Failed to create DNS resolver", log.Fields{"error": err})
	}

	service := handlers.NewWorkerService(messageBusServer, db, resolver, cfg)
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
			log.Info("Starting health check server for hosting provision worker")
			err = healthCheckServer.Start(context.Background())
			if err != nil {
				log.Fatal("Error occurred while starting health check server for hosting provision worker", log.Fields{"error": err})
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
