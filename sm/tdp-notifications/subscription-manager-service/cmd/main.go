package main

import (
	"fmt"
	"github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/config"
	"github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/handlers/rpc"
	"github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/service"
	logging "github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/logger/zap"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
	"os"
	"os/signal"
	"syscall"
)

const configPath = "configs"

func main() {

	cfg, err := config.LoadConfiguration(configPath)
	logger := zap.NewTdpLogger(cfg.Log) // Log config is loaded by default values anyway
	if err != nil {
		logger.Fatal("failed to load tdp-notifications subscription-manager-service configuration: %v", logging.Fields{"error": err})
	}

	logger.Info("configuration successfully loaded, starting tdp-notifications subscription-manager-service...")

	if err := run(&cfg, logger); err != nil {
		logger.Fatal("error running service", logging.Fields{"error": err})
	}

}

func run(cfg *config.Config, logger logging.ILogger) error {
	defer logger.Sync() //  flushes the log buffer before shutting down

	domainsDB, err := database.New(cfg.DomainsDB.PostgresPoolConfig(), logger)
	if err != nil {
		return fmt.Errorf("failed to create connection to Domains DB: %w", err)
	}
	defer domainsDB.Close()

	subDB, err := database.New(cfg.SubscriptionDB.PostgresPoolConfig(), logger)
	if err != nil {
		return fmt.Errorf("failed to create connection to Subscription DB: %w", err)
	}
	defer subDB.Close()

	srvc, err := service.New(domainsDB, subDB, cfg)
	if err != nil {
		return fmt.Errorf("failed to create subscription service: %w", err)
	}

	bus, err := rpc.New(cfg, srvc, logger)
	if err != nil {
		return fmt.Errorf("failed to registering messagebus: %w", err)
	}
	defer bus.Dispose()

	errChan := make(chan error, 10)
	signalChan := make(chan os.Signal, 1)
	signal.Notify(signalChan, os.Interrupt, syscall.SIGTERM)

	go func() {
		err = bus.Consume([]string{cfg.RMQ.QueueName})
		if err != nil {
			errChan <- fmt.Errorf("error occurred while consuming from message bus: %w", err)
		}
	}()

	select {
	case err = <-errChan:
		return err
	case <-signalChan:

		logger.Info("gracefully shutting down tdp-notifications/subscription-manager-service...")
		return nil
	}
}
