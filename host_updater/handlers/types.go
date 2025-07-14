package handlers

import (
	"github.com/alexliesenfeld/health"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message"
	rymessages "github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	defaulthandlers "github.com/tucowsinc/tdp-workers-go/pkg/handlers"
	mb "github.com/tucowsinc/tdp-workers-go/pkg/message_bus"
)

type WorkerService struct {
	db     database.Database
	bus    messagebus.MessageBus
	tracer *oteltrace.Tracer
}

func NewWorkerService(bus messagebus.MessageBus, db database.Database, tracer *oteltrace.Tracer) *WorkerService {
	return &WorkerService{
		db:     db,
		bus:    bus,
		tracer: tracer,
	}
}

// RegisterHandlers registers the handlers for the service.
func (s *WorkerService) RegisterHandlers() {
	s.bus.Register(
		&rymessages.HostCreateResponse{},
		s.RyHostProvisionHandler,
	)

	s.bus.Register(
		&rymessages.HostUpdateResponse{},
		s.RyHostUpdateHandler,
	)

	s.bus.Register(
		&rymessages.HostCheckResponse{},
		s.RyHostCheckHandler,
	)

	s.bus.Register(
		&rymessages.HostDeleteResponse{},
		s.RyHostDeleteHandler,
	)

	s.bus.Register(
		&message.ErrorResponse{},
		defaulthandlers.ErrorResponseHandler(s.db),
	)
}

// HealthChecks returns a slice of health checks for the service.
func (s *WorkerService) HealthChecks(cfg config.Config) (checks []health.Check) {
	return []health.Check{
		database.HealthCheck(s.db),
		mb.HealthCheck(cfg.RmqUrl()),
	}
}
