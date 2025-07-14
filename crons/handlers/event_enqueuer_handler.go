package handlers

import (
	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"

	"github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/worker"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

const DefaultUnProcessedEventBatchSize = 100

func EventEnqueueHandler(event *model.VEventUnprocessed) (msg proto.Message, err error) {
	eventLogger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CronType: CronServiceTypeNameEnum.EventEnqueueCron,
		types.LogFieldKeys.TenantID: event.TenantID,
		types.LogFieldKeys.LogID:    uuid.NewString(),
		"event_id":                  event.ID,
		"event_type":                event.EventTypeName,
	})

	eventLogger.Info("Received new event for processing")

	switch event.EventTypeName {
	case "domain_transfer":
		msg, err = handleDomainTransferEvent(event, eventLogger)
	default:
		eventLogger.Warn("unsupported event type")
	}
	if err != nil {
		eventLogger.Error("Error processing event", log.Fields{types.LogFieldKeys.Error: err})
		return
	}

	eventLogger.Info("Successfully processed event")

	return
}

func handleDomainTransferEvent(event *model.VEventUnprocessed, logger logger.ILogger) (msg *worker.NotificationMessage, err error) {
	payload, err := types.ParseJSON[DomainTransferEvent](event.Payload)
	if err != nil {
		logger.Error("Error parsing domain transfer event payload", log.Fields{types.LogFieldKeys.Error: err})
		return
	}

	notificationMsg := &common.TransferNotification{
		Name:          payload.Name,
		Status:        payload.Status,
		RequestedBy:   payload.RequestedBy,
		RequestedDate: types.ToTimestampMsg(payload.RequestedDate),
		ActionBy:      payload.ActionBy,
		ActionDate:    types.ToTimestampMsg(payload.ActionDate),
		ExpiryDate:    types.ToTimestampMsg(payload.ExpiryDate),
	}

	notificationData, _ := anypb.New(notificationMsg)

	msg = &worker.NotificationMessage{
		Type:     types.NotificationType.DomainTransfer,
		Data:     notificationData,
		TenantId: event.TenantID,
	}

	return
}
