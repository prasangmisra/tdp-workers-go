package handlers

import (
	"context"
	"errors"
	"github.com/alexliesenfeld/health"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/worker"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/memoizelib"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	mb "github.com/tucowsinc/tdp-workers-go/pkg/message_bus"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

const (
	AccreditationCacheTTL     = 300 // 5 min
	AccreditationCacheMaxKeys = 50  // max number of accreditation objects in memory
)

var LogFieldKeys = struct {
	Accreditation,
	PollMessageID,
	PollMessageType string
}{
	Accreditation:   "poll_message_accreditation",
	PollMessageID:   "poll_message_id",
	PollMessageType: "poll_message_type",
}

var PollMessageType = struct {
	Transfer,
	Renewal,
	PendingAction,
	DomainInfo,
	HostInfo,
	ContactInfo,
	Unspec string
}{
	"transfer",
	"renewal",
	"pending_action",
	"domain_info",
	"host_info",
	"contact_info",
	"unspec",
}

var TransferStatus = struct {
	ClientApproved,
	ClientCancelled,
	ClientRejected,
	Pending,
	ServerApproved,
	ServerCancelled string
}{
	"clientApproved",
	"clientCancelled",
	"clientRejected",
	"pending",
	"serverApproved",
	"serverCancelled",
}

var ErrTempRyFailure = errors.New("temporary ry failure")
var ErrDeferMessage = errors.New("defers poll message processing")

// PollHandler represents poll handler interface
type PollHandler interface {
	Matches(*worker.PollMessage) bool
	Handle(context.Context, *WorkerService, *worker.PollMessage, logger.ILogger) error
}

// UnspecPollMessageTypePatternMap contains map of unspec type poll messages to figure out handler type
var UnspecPollMessageTypePatternMap = map[string][]string{
	PollMessageType.Renewal:       {"auto-renewed"},
	PollMessageType.PendingAction: {"Restore Completed", "Restore Rejected"},
}

// WorkerService holds all required dependencies for service to use
type WorkerService struct {
	cfg              config.Config
	db               database.Database
	bus              messagebus.MessageBus
	getAccreditation memoizelib.Cached[*model.Accreditation]
	pollHandlers     []PollHandler
	tracer           *oteltrace.Tracer
}

// NewWorkerService creates and returns instance of worker service
func NewWorkerService(bus messagebus.MessageBus, db database.Database, tracer *oteltrace.Tracer, cfg config.Config) *WorkerService {
	PollHandlers := []PollHandler{
		// NewAutoRenewHandler(), // We don't support auto-renewal poll messages processing at the moment.
		NewPendingActionHandler(),
		NewTransferHandler(),
	}

	return &WorkerService{
		cfg:              cfg,
		db:               db,
		bus:              bus,
		getAccreditation: memoizelib.New[*model.Accreditation](AccreditationCacheTTL, AccreditationCacheMaxKeys),
		pollHandlers:     PollHandlers,
		tracer:           tracer,
	}
}

// GetDomainName gets domain name from poll message
func GetDomainName(request *worker.PollMessage) (domainName string) {
	if request.GetRenData() != nil && request.GetRenData().Name != "" {
		domainName = request.GetRenData().Name
	} else if request.GetPanData() != nil && request.GetPanData().Name != "" {
		domainName = request.GetPanData().Name
	} else {
		domainName = types.ExtractDomainName(request.Msg)
	}

	return
}

// RegisterHandlers registers the handlers for the service.
func (s *WorkerService) RegisterHandlers() {
	// handler to process poll messages from ry
	s.bus.Register(
		&ryinterface.EppPollMessage{},
		s.RyPollMessageHandler,
	)

	// handler to process poll messages from database
	s.bus.Register(
		&worker.PollMessage{},
		s.PollMessageHandler,
	)
}

// HealthChecks returns a slice of health checks for the service.
func (s *WorkerService) HealthChecks() (checks []health.Check) {
	return []health.Check{
		database.HealthCheck(s.db),
		mb.HealthCheck(s.cfg.RmqUrl()),
	}
}
