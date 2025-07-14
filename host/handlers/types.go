package handlers

import (
	"context"
	"fmt"

	"github.com/alexliesenfeld/health"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	rymessages "github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	mb "github.com/tucowsinc/tdp-workers-go/pkg/message_bus"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
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
	// notifications from database
	s.bus.Register(
		&job.Notification{}, // go type for the message
		s.HandlerRouter,     // handler function
	)
}

// HealthChecks returns a slice of health checks for the service.
func (s *WorkerService) HealthChecks(cfg config.Config) (checks []health.Check) {
	return []health.Check{
		database.HealthCheck(s.db),
		mb.HealthCheck(cfg.RmqUrl()),
	}
}

func (s *WorkerService) getHostInfo(ctx context.Context, hostName string, accName string) (*rymessages.HostInfoResponse, error) {
	hostInfoMsg := &rymessages.HostInfoRequest{Name: hostName}
	q := types.GetQueryQueue(accName)
	response, err := mb.Call(ctx, s.bus, q, hostInfoMsg)
	if err != nil {
		return nil, err
	}

	hostInfoResp, ok := response.(*rymessages.HostInfoResponse)
	if !ok {
		return nil, fmt.Errorf("unexpected message type received for host info response: %T", response)
	}

	return hostInfoResp, nil
}
