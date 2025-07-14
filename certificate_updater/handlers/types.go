package handlers

import (
	"github.com/alexliesenfeld/health"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	certmessages "github.com/tucowsinc/tdp-messages-go/message/certbot"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
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
func (s *WorkerService) RegisterHandlers() (checks []health.Check) {
	s.bus.Register(
		&certmessages.CertificateIssuedNotification{},
		s.CertificateCreateResponseHandler,
	)

	s.bus.Register(
		&certmessages.CertificateRenewedNotification{},
		s.CertificateRenewResponseHandler,
	)

	return
}

// HealthChecks returns a slice of health checks for the service.
func (s *WorkerService) HealthChecks(cfg config.Config) (checks []health.Check) {
	return []health.Check{
		database.HealthCheck(s.db),
		mb.HealthCheck(cfg.RmqUrl()),
	}
}
