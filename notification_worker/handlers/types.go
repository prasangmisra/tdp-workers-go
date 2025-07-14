package handlers

import (
	"github.com/alexliesenfeld/health"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/worker"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	mb "github.com/tucowsinc/tdp-workers-go/pkg/message_bus"
	"github.com/tucowsinc/tdp-workers-go/pkg/repository"
	"github.com/tucowsinc/tdp-workers-go/pkg/repository/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/repository/model"
)

type WorkerService struct {
	db                 database.Database
	bus                messagebus.MessageBus
	notificationRepo   repository.IRepository[*model.Notification]
	subscriptionRepo   repository.IRepository[*model.Subscription]
	notificationTypeLT repository.ILookupTable[*model.NotificationType]
	tracer             *oteltrace.Tracer
}

func NewWorkerService(bus messagebus.MessageBus, db database.Database, tracer *oteltrace.Tracer) (service *WorkerService, err error) {
	notificationTypeLT, err := repository.NewLookupTable[*model.NotificationType](db)
	if err != nil {
		log.Error("Failed to create notification type lookup table", log.Fields{"error": err})
		return
	}

	service = &WorkerService{
		db:                 db,
		bus:                bus,
		notificationRepo:   repository.NewRepository[*model.Notification](db),
		subscriptionRepo:   repository.NewRepository[*model.Subscription](db),
		notificationTypeLT: notificationTypeLT,
		tracer:             tracer,
	}

	return
}

// RegisterHandlers registers the handlers for the service.
func (s *WorkerService) RegisterHandlers() {
	// handler to process notification messages
	s.bus.Register(
		&worker.NotificationMessage{},
		s.NotificationHandler,
	)
}

// HealthChecks returns a slice of health checks for the service.
func (s *WorkerService) HealthChecks(cfg config.Config) (checks []health.Check) {
	return []health.Check{
		database.HealthCheck(s.db),
		mb.HealthCheck(cfg.RmqUrl()),
	}
}
