package handlers

import (
	"github.com/google/uuid"
	sqlx "github.com/jmoiron/sqlx/types"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/worker"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/repository/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// NotificationHandler inserts incoming notifications into database
func (service *WorkerService) NotificationHandler(server messagebus.Server, message proto.Message) (err error) {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "NotificationHandler")
	defer service.tracer.FinishSpan(span)

	// We need to type-cast the proto.Message to the wanted type
	request := message.(*worker.NotificationMessage)

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.LogID:    uuid.NewString(),
		types.LogFieldKeys.JobType:  request.Type,
		types.LogFieldKeys.TenantID: request.TenantId,
	})

	logger.Debug("Received notification message", log.Fields{
		types.LogFieldKeys.Message: request.String(),
	})

	notificationTypeID := service.notificationTypeLT.GetIdByName(request.Type)
	if notificationTypeID == "" {
		logger.Warn("Invalid job type")
		return
	}

	notificationMsg, err := request.Data.UnmarshalNew()
	if err != nil {
		logger.Error(types.LogMessages.JSONDecodeFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	var payload sqlx.JSONText
	payload, err = protojson.Marshal(notificationMsg)
	if err != nil {
		logger.Error("Error marshaling notification data to JSON", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	// Need to check if the tenant_customer_id was set;
	// if it wasn't we shouldn't try to persist that field
	var notification model.Notification = model.Notification{
		TypeID:   notificationTypeID,
		TenantID: request.TenantId,
		Payload:  &payload,
	}
	if types.SafeDeref(request.TenantCustomerId) != "" {
		// Since it was provided, set the tenant_customer_id here
		notification.TenantCustomerID = request.TenantCustomerId
	}

	err = service.notificationRepo.Create(ctx, &notification)
	if err != nil {
		logger.Error("Error creating notification in the database", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	logger.Info("Notification successfully created in the database")

	return
}
