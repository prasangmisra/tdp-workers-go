package main

import (
	"fmt"
	"github.com/tucowsinc/tdp-notifications/email-sender-service/internal/app/infrastracture/smtp"
	"os"
	"os/signal"
	"syscall"

	"github.com/tucowsinc/tdp-notifications/email-sender-service/internal/app/config"
	"github.com/tucowsinc/tdp-notifications/email-sender-service/internal/app/handlers/consumer"

	v1 "github.com/tucowsinc/tdp-notifications/email-sender-service/internal/app/handlers/consumer/v1"
	"github.com/tucowsinc/tdp-notifications/email-sender-service/internal/app/service"

	logging "github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/logger/zap"
)

const configPath = "configs"

func main() {
	cfg, err := config.LoadConfiguration(configPath)
	logger := zap.NewTdpLogger(cfg.Log)

	if err != nil {
		logger.Fatal("failed to load email-sender-service configuration", logging.Fields{"error": err})
	}

	logger.Info("Configuration loaded, starting email-sender-service...")

	if err := run(&cfg, logger); err != nil {
		logger.Fatal("error running email sender service", logging.Fields{"error": err})
	}
}

func run(cfg *config.Config, logger logging.ILogger) error {
	defer logger.Sync()

	bus, err := consumer.New(cfg, logger)
	if err != nil {
		return fmt.Errorf("failed to register message bus: %w", err)
	}
	defer bus.Finalize()

	smtpClient := smtp.NewClient(cfg.SMTPServer)
	srvc := service.New(logger, smtpClient, bus, cfg.RMQ.FinalStatusQueue.Name)

	handler := v1.NewHandler(srvc, logger)

	handler.RegisterHandlers(bus)

	errChan := make(chan error, 10)
	signalChan := make(chan os.Signal, 1)
	signal.Notify(signalChan, os.Interrupt, syscall.SIGTERM)

	go func() {
		err = bus.Consume([]string{cfg.RMQ.EmailSendQueue.Name})
		if err != nil {
			errChan <- fmt.Errorf("error occurred while consuming from message bus: %w", err)
		}
	}()

	select {
	case err = <-errChan:
		return err
	case <-signalChan:
		logger.Info("gracefully shutting down email-sender-service...")
		return nil
	}
}
