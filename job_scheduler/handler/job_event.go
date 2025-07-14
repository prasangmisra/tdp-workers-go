package handler

import (
	"context"

	"github.com/google/uuid"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

func (s *WorkerService) JobEventNotifyHandler(event *types.JobEvent) (err error) {
	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.LogID:   uuid.NewString(),
		types.LogFieldKeys.JobID:   event.JobId,
		types.LogFieldKeys.JobType: event.Type,
		"routing_key":              event.RoutingKey,
		"reference_id":             event.ReferenceId,
		"reference_table":          event.ReferenceTable,
	})
	span, headers := tracing.CreateSpanFromMetaData(event, s.tracer, "JobEventNotifyHandler")
	defer s.tracer.FinishSpan(span)
	jobNotification := job.Notification{
		JobId:          event.JobId,
		Type:           event.Type,
		Status:         event.Status,
		ReferenceId:    event.ReferenceId,
		ReferenceTable: event.ReferenceTable,
	}

	err = s.bus.Send(context.Background(), event.RoutingKey, &jobNotification, headers)
	if err != nil {
		logger.Error("Failed to send job notification", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	logger.Info("Successfully sent job notification")

	return nil
}
