package main

import (
	"context"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	"github.com/tucowsinc/tdp-workers-go/crons/handlers"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
)

func main() {
	cfg, err := config.LoadConfiguration(".env")

	log.Setup(cfg)
	defer log.Sync()

	log.Info("Starting cron worker")

	if err != nil {
		log.Fatal(types.LogMessages.ConfigurationLoadFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}

	log.Info(types.LogMessages.ConfigurationLoaded)

	service, err := handlers.NewCronService(cfg)
	if err != nil {
		log.Fatal("Failed to instantiate service", log.Fields{"error": err})
	}

	defer service.Close()

	err = service.CronRouter(context.Background())
	if err != nil {
		log.Error("Error occurred", log.Fields{"error": err})
	} else {
		log.Info("Cron job completed successfully")
	}

	log.Info(types.LogMessages.WorkerTerminated)
}
