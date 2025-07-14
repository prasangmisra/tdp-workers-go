package main

import (
	"context"
	"fmt"
	"os"

	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	mb "github.com/tucowsinc/tdp-workers-go/pkg/message_bus"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
	"github.com/tucowsinc/tdp-workers-go/poll_enqueuer/handler"
)

func main() {
	cfg, err := config.LoadConfiguration(".env")
	if err != nil {
		panic(fmt.Errorf("error loading configuration: %v", err))
	}
	log.Setup(cfg)
	defer log.Sync()
	log.Info(types.LogMessages.ConfigurationLoaded)
	log.Info("Starting poll enqueuer worker")

	bus, err := mb.SetupMessageBus(cfg)
	if err != nil {
		log.Fatal(types.LogMessages.MessageBusSetupFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}
	defer bus.Finalize()

	db, err := database.New(cfg.PostgresPoolConfig(), cfg.GetDBLogLevel())
	if err != nil {
		log.Error(types.LogMessages.DatabaseConnectionFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
		os.Exit(1)
	}
	defer db.Close()

	service := handler.NewWorkerService(bus, db)

	enq, err := service.GetEnqueuer(cfg)
	if err != nil {
		log.Error("Error configuring enqueuer", log.Fields{
			types.LogFieldKeys.Error: err.Error(),
		})
		return
	}

	log.Info("Starting enqueuer...")
	err = enq.EnqueuerDbMessages(context.Background(), service.DBPollMessageHandler)
	if err != nil {
		log.Fatal("Error starting enqueuer", log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}
	log.Info("Finished enqueuing messages, exiting...")
}
