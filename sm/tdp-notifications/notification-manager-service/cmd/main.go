package main

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/tucowsinc/tdp-notifications/notification-manager-service/internal/app/config"
	consumer "github.com/tucowsinc/tdp-notifications/notification-manager-service/internal/app/handlers/consumer"
	v1 "github.com/tucowsinc/tdp-notifications/notification-manager-service/internal/app/handlers/consumer/v1"
	"github.com/tucowsinc/tdp-notifications/notification-manager-service/internal/app/service"
	logging "github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/logger/zap"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
)

const configPath = "configs"

func main() {

	cfg, err := config.LoadConfiguration(configPath)
	logger := zap.NewTdpLogger(cfg.Log) // Log config is loaded by default values anyway
	if err != nil {
		logger.Fatal("failed to load tdp-notifications notification-manager-service configuration", logging.Fields{"error": err})
	}

	logger.Info("configuration successfully loaded, starting tdp-notifications notification-manager-service...")

	if err := run(&cfg, logger); err != nil {
		logger.Fatal("error running service", logging.Fields{"error": err})
	}

}

func run(cfg *config.Config, logger logging.ILogger) error {
	defer logger.Sync() //  flushes the log buffer before shutting down

	subDB, err := database.New(cfg.SubscriptionDB.PostgresPoolConfig(), logger)
	if err != nil {
		return fmt.Errorf("failed to create connection to Subscription DB: %w", err)
	}
	defer subDB.Close()
	bus, err := consumer.New(cfg, logger)
	if err != nil {
		return fmt.Errorf("failed to register messagebus: %w", err)
	}
	defer bus.Finalize()

	srvc, err := service.New(logger, subDB)
	if err != nil {
		return fmt.Errorf("failed to create notification manager service: %w", err)
	}
	handler := v1.NewHandler(srvc, logger, *cfg, bus)
	handler.Register()
	errChan := make(chan error, 10)
	signalChan := make(chan os.Signal, 1)
	signal.Notify(signalChan, os.Interrupt, syscall.SIGTERM)

	go func() {
		err = bus.Consume([]string{cfg.RMQ.FinalStatusQueue.Name, cfg.RMQ.EmailRenderingQueue.Name})
		if err != nil {
			errChan <- fmt.Errorf("error occurred while consuming from message bus: %w", err)
		}
	}()

	select {
	case err = <-errChan:
		return err
	case <-signalChan:
		logger.Info("gracefully shutting down tdp-notifications/notification-manager-service...")
		return nil
	}
}
