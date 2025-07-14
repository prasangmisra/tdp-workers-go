package main

import (
	"context"
	"fmt"
	"time"

	"github.com/tucowsinc/tdp-shared-go/healthcheck"

	"github.com/tucowsinc/tdp-workers-go/hosting_updater/handlers"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
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

	log.Info("Starting hosting provision updater worker")

	db, err := database.New(cfg.PostgresPoolConfig(), cfg.GetDBLogLevel())
	if err != nil {
		log.Fatal(types.LogMessages.DatabaseConnectionFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}
	defer db.Close()

	sqsConsumer := handlers.SetupSQSConsumer(context.Background(), cfg)

	service := handlers.NewWorkerService(sqsConsumer, db)
	service.RegisterHandlers()

	if cfg.HealthcheckEnabled {
		healthCheckServer := healthcheck.New(cfg.HealthcheckPort)

		for _, check := range service.HealthChecks() {
			healthCheckServer.RegisterHealthCheck(
				check,
				healthcheck.WithFrequency(time.Duration(cfg.HealthcheckInterval)*time.Second),
				healthcheck.WithTimeout(time.Duration(cfg.HealthcheckTimeout)*time.Second),
			)
		}

		go func() {
			log.Info("Starting health check server for hosting provision updater worker")
			err = healthCheckServer.Start(context.Background())
			if err != nil {
				log.Fatal("Error occurred while starting health check server for hosting provision updater worker", log.Fields{"error": err})
			}
		}()
	}

	log.Info(types.LogMessages.ConsumingQueuesStarted, log.Fields{
		types.LogFieldKeys.Queue: cfg.AWSSqsQueueName,
	})
	sqsConsumer.Consume()

	log.Info(types.LogMessages.WorkerTerminated)
}
