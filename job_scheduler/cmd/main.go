package main

import (
	"context"

	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	"github.com/tucowsinc/tdp-shared-go/healthcheck"

	"github.com/tucowsinc/tdp-workers-go/job_scheduler/handler"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	pgevent "github.com/tucowsinc/tdp-workers-go/pkg/pgevents"
)

const (
	JobCheckInterval = 30 * time.Second
)

func main() {
	cfg, err := config.LoadConfiguration(".env")
	if err != nil {
		panic(fmt.Errorf("error loading configuration: %v", err))
	}
	log.Setup(cfg)
	defer log.Sync()
	log.Info(types.LogMessages.ConfigurationLoaded)

	log.Info("Starting job scheduler worker")

	tracer, otelShutdown, err := tracing.Setup(context.Background(), cfg)
	if err != nil {
		log.Fatal("Error setting up tracing", log.Fields{"error": err})
	}
	defer func() {
		err = oteltrace.JoinErrors(err, otelShutdown(context.Background()))
		log.Error("error is: ", log.Fields{"error": err})
	}()

	ctx := context.Background()

	ticker := time.NewTicker(JobCheckInterval)
	defer ticker.Stop()

	notificationHandler := handler.NewNotificationHandler(cfg, tracer)
	defer notificationHandler.Close()

	listener, err := pgevent.New(cfg.DBConnStr())
	if err != nil {
		log.Fatal("Error creating listener", log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}
	defer listener.Close(ctx)

	listener.RegisterHandler("job_event", notificationHandler)

	errCh := make(chan error, 10)
	signalCh := make(chan os.Signal, 1)
	signal.Notify(signalCh, os.Interrupt, syscall.SIGTERM)

	go func() {
		err := listener.StartListening(ctx)
		if err != nil {
			errCh <- fmt.Errorf("error listening for notifications: %v", err)
		}
	}()

	go func() {
		for {
			select {
			case t := <-ticker.C:
				if err := notificationHandler.Service.CheckStaleJobs(t); err != nil {
					errCh <- fmt.Errorf("error checking stale jobs: %v", err)
					break
				}
			}
		}
	}()

	if cfg.HealthcheckEnabled {
		healthCheckServer := healthcheck.New(cfg.HealthcheckPort)

		for _, check := range notificationHandler.HealthChecks(cfg) {
			healthCheckServer.RegisterHealthCheck(
				check,
				healthcheck.WithFrequency(time.Duration(cfg.HealthcheckInterval)*time.Second),
				healthcheck.WithTimeout(time.Duration(cfg.HealthcheckTimeout)*time.Second),
			)
		}

		go func() {
			log.Info("Starting health check server for job scheduler worker")
			err = healthCheckServer.Start(context.Background())
			if err != nil {
				errCh <- fmt.Errorf("error occurred while starting health check server for job scheduler worker: %v", err)
			}
		}()
	}

	select {
	case err := <-errCh:
		log.Error("Error occurred", log.Fields{"error": err})
	case <-signalCh:
		log.Info("Received termination signal. Shutting down gracefully...")
	}
}
