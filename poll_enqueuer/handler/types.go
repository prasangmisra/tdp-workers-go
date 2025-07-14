package handler

import (
	"time"

	"github.com/alexliesenfeld/health"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/enqueuer"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	mb "github.com/tucowsinc/tdp-workers-go/pkg/message_bus"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

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

type WorkerService struct {
	db  database.Database
	bus messagebus.MessageBus
}

func NewWorkerService(bus messagebus.MessageBus, db database.Database) *WorkerService {
	return &WorkerService{
		db:  db,
		bus: bus,
	}
}

// GetEnqueuer returns a new enqueuer for poll messages.
func (s *WorkerService) GetEnqueuer(config config.Config) (enq enqueuer.DbMessageEnqueuer[*model.PollMessage], err error) {
	pendingStatusID := s.db.GetPollMessageStatusId(types.PollMessageStatus.Pending)
	submittedStatusID := s.db.GetPollMessageStatusId(types.PollMessageStatus.Submitted)

	enqueuerConfig, err := enqueuer.NewDbEnqueuerConfigBuilder[*model.PollMessage]().
		WithQueryExpression("status_id = ? OR (status_id = ? AND last_submitted_date <= ?)").
		WithQueryValues([]any{
			pendingStatusID,
			submittedStatusID,
			time.Now().Add(-10 * time.Minute),
		}).
		WithUpdateFieldValueMap(map[string]interface{}{
			"last_submitted_date": time.Now(),
			"status_id":           submittedStatusID},
		).
		WithOrderByExpression("created_date").
		WithQueue(config.RmqQueueName).
		Build()
	if err != nil {
		log.Error("Error configuring enqueuer", log.Fields{"error": err})
		return
	}

	enq = enqueuer.DbMessageEnqueuer[*model.PollMessage]{
		Db:     s.db.GetDB(),
		Bus:    s.bus,
		Config: enqueuerConfig,
	}

	return
}

// HealthChecks returns a slice of health checks for the service.
func (s *WorkerService) HealthChecks(cfg config.Config) (checks []health.Check) {
	return []health.Check{
		database.HealthCheck(s.db),
		mb.HealthCheck(cfg.RmqUrl()),
	}
}
