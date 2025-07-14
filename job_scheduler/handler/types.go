package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/alexliesenfeld/health"
	"github.com/google/uuid"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	message_bus "github.com/tucowsinc/tdp-workers-go/pkg/message_bus"
	pgevent "github.com/tucowsinc/tdp-workers-go/pkg/pgevents"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

type WorkerService struct {
	db     database.Database
	bus    messagebus.MessageBus
	tracer *oteltrace.Tracer
}

type NotificationHandler struct {
	Service *WorkerService
}

func NewWorkerService(cfg config.Config, tracer *oteltrace.Tracer) *WorkerService {

	// Instantiate a messagebus
	messagebusServer, err := message_bus.SetupMessageBus(cfg)
	if err != nil {
		log.Fatal("Cannot initialize message bus", log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}

	db, err := database.New(cfg.PostgresPoolConfig(), cfg.GetDBLogLevel())
	if err != nil {
		log.Fatal(types.LogMessages.DatabaseConnectionFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}
	log.Info("WorkerService initialized successfully")

	return &WorkerService{
		bus:    messagebusServer,
		db:     db,
		tracer: tracer,
	}
}

func NewNotificationHandler(config config.Config, tracer *oteltrace.Tracer) *NotificationHandler {
	service := NewWorkerService(config, tracer)

	return &NotificationHandler{Service: service}
}

// CheckStaleJobs checks for stale jobs.
func (s *WorkerService) CheckStaleJobs(t time.Time) (err error) {
	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.LogID: uuid.NewString(),
		"component":              "CheckStaleJobs",
	})
	staleJobs, err := s.db.GetStaleJobs(context.Background())
	if err != nil {
		logger.Fatal("Error querying stale jobs", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	for _, staleJob := range staleJobs {
		logger.Info("Stale job re-queued",
			log.Fields{
				types.LogFieldKeys.JobID:  staleJob.JobID,
				types.LogFieldKeys.Status: staleJob.JobStatusName,
				"checked":                 t,
			},
		)
	}
	return nil
}

// HandleNotification handles a notification event.
func (h *NotificationHandler) HandleNotification(notification *pgevent.Notification) error {
	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.LogID: uuid.NewString(),
		"component":              "HandleNotification",
		"event":                  notification.Type,
	})
	switch notification.Type {
	case "job_event_notify":
		event := new(types.JobEvent)
		if err := json.Unmarshal([]byte(notification.Payload), event); err != nil {
			logger.Error("Failed to unmarshal notification payload", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return fmt.Errorf("failed to unmarshal JSON: %s", err.Error())
		}
		logger.Info("Processing job event notification", log.Fields{
			types.LogFieldKeys.JobID: event.JobId,
			"event_type":             event.Type,
		})
		return h.Service.JobEventNotifyHandler(event)
	default:
		errMsg := fmt.Sprintf("Unknown event type: %s", notification.Type)
		logger.Warn(errMsg)
		return fmt.Errorf(errMsg)
	}
}

// HealthChecks returns a slice of health checks for the service.
func (h *NotificationHandler) HealthChecks(cfg config.Config) (checks []health.Check) {
	return []health.Check{
		database.HealthCheck(h.Service.db),
		message_bus.HealthCheck(cfg.RmqUrl()),
	}
}

// Close closes the notification handler.
func (h *NotificationHandler) Close() {
	h.Service.db.Close()
}
