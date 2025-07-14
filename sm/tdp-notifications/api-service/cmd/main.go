package main

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"

	docs "github.com/tucowsinc/tdp-notifications/api-service/api"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/app/handlers/rest"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/app/service"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/config"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/messaging"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/validators"
	logging "github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/logger/zap"
)

const configPath = "configs"

// @title 			Domains Notifications and Subscriptions API
// @version 		1.0
// @description 	Manage domain notifications and subscriptions

// @contact.name	Tucows Domains Support
// @contact.email	support@tucows.com
// @contact.url		https://www.tucows.com/
func main() {

	cfg, err := config.LoadConfiguration(configPath)
	logger := zap.NewTdpLogger(cfg.Log) // Log config is loaded by default values anyway
	if err != nil {
		logger.Fatal("failed to load tdp-notifications api service configuration: %v", logging.Fields{"error": err})
	}

	logger.Info("configuration successfully loaded, starting tdp-notifications api service...")

	if err := run(&cfg, logger); err != nil {
		logger.Fatal("error running service", logging.Fields{"error": err})
	}

}

func run(cfg *config.Config, logger logging.ILogger) error {
	defer logger.Sync() //  flushes the log buffer before shutting down

	if err := validators.RegisterValidators(cfg); err != nil {
		return fmt.Errorf("error registering validators: %w", err)
	}

	docs.SwaggerInfo.BasePath = "/"

	bus, err := messaging.New(cfg)
	if err != nil {
		return fmt.Errorf("failed to registering messagebus: %w", err)
	}
	defer bus.Dispose()

	srvc := service.New(bus, cfg.RMQ.QueueName)
	router := rest.NewRouter(srvc, cfg, logger)

	errChan := make(chan error, 10)
	signalChan := make(chan os.Signal, 1)
	signal.Notify(signalChan, os.Interrupt, syscall.SIGTERM)

	go func() {
		err = router.Run(":" + cfg.ServicePort)
		if err != nil {
			errChan <- fmt.Errorf("error occurred while running HTTP REST API: %w", err)
		}
	}()

	select {
	case err = <-errChan:
		return err
	case <-signalChan:

		logger.Info("gracefully shutting down tdp-notifications api service...")
		return nil
	}
}
