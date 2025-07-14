package handlers

import (
	"context"
	"fmt"
	"strconv"

	"github.com/alexliesenfeld/health"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	rymessages "github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	mb "github.com/tucowsinc/tdp-workers-go/pkg/message_bus"
)

var LocksToEppStatus = map[string]string{
	"update":   "clientUpdateProhibited",
	"delete":   "clientDeleteProhibited",
	"transfer": "clientTransferProhibited",
	"renew":    "clientRenewProhibited",
	"hold":     "clientHold",
}

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

func getBoolAttribute(tx database.Database, ctx context.Context, attributeName string, accTldId string) (*bool, error) {
	// get the TLD setting
	tldSetting, err := tx.GetTLDSetting(
		ctx,
		accTldId,
		attributeName,
	)
	if err != nil {
		log.Error("Failed to get Tld setting", log.Fields{
			types.LogFieldKeys.Error: err.Error(),
		})
		return nil, err
	}

	// parse the TLD setting value
	parsedValue := false
	if tldSetting == nil {
		return &parsedValue, nil
	}

	parsedValue, err = strconv.ParseBool(tldSetting.Value)
	if err != nil {
		log.Error("Failed to parse Tld setting value", log.Fields{
			types.LogFieldKeys.Error: err.Error(),
		})
		return nil, err
	}

	return &parsedValue, err
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

func (s *WorkerService) getDomainInfo(ctx context.Context, domainName string, accName string) (*rymessages.DomainInfoResponse, error) {
	domainInfoMsg := &rymessages.DomainInfoRequest{Name: domainName}
	response, err := mb.Call(ctx, s.bus, types.GetQueryQueue(accName), domainInfoMsg)
	if err != nil {
		return nil, err
	}

	domainInfoResp, ok := response.(*rymessages.DomainInfoResponse)
	if !ok {
		return nil, fmt.Errorf("unexpected message type received for domain info response: %T", response)
	}

	return domainInfoResp, nil
}
