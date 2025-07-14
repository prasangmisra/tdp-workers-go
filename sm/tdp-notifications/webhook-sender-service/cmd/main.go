package main

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/app/config"
	"github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/app/handlers/consumer"
	v1 "github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/app/handlers/consumer/v1"
	"github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/app/service"
	"github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/pkg/rest"
	logging "github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/logger/zap"
)

const configPath = "configs"

func main() {
	cfg, err := config.LoadConfiguration(configPath)
	logger := zap.NewTdpLogger(cfg.Log)

	if err != nil {
		logger.Fatal("failed to load webhook-sender-service configuration", logging.Fields{"error": err})
	}

	logger.Info("Configuration loaded, starting webhook-sender-service...")

	if err := run(&cfg, logger); err != nil {
		logger.Fatal("error running webhook sender service", logging.Fields{"error": err})
	}
}

func run(cfg *config.Config, logger logging.ILogger) error {
	defer logger.Sync()

	bus, err := consumer.New(cfg, logger)
	if err != nil {
		return fmt.Errorf("failed to register message bus: %w", err)
	}
	defer bus.Finalize()
	httpClient := rest.New(cfg.HTTP.Timeout)
	srvc := service.New(cfg, logger, bus, httpClient)

	handler := v1.NewHandler(srvc, logger)
	handler.RegisterHandlers()
	errChan := make(chan error, 10)
	signalChan := make(chan os.Signal, 1)
	signal.Notify(signalChan, os.Interrupt, syscall.SIGTERM)

	go func() {
		err = bus.Consume([]string{cfg.RMQ.WebhookSendQueue.Name})
		if err != nil {
			errChan <- fmt.Errorf("error occurred while consuming from message bus: %w", err)
		}
	}()

	select {
	case err = <-errChan:
		return err
	case <-signalChan:
		logger.Info("gracefully shutting down webhook-sender-service...")
		return nil
	}
}
