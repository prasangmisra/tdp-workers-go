package handlers

import (
	"errors"

	"github.com/google/uuid"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/sqs"
	hostingproto "github.com/tucowsinc/tucows-domainshosting-app/cmd/functions/order/proto"
)

// Those are the only statuses that are sent in the hosting order details response from the hosting api
// https://github.com/tucowsinc/tucows-domainshosting-app/blob/dev/cmd/functions/provisioner-update/services/provisioner_callback_service.go#L49
var orderStatusToProvisionHostingCreateStatus = map[string]string{
	types.OrderStatusHostingAPI.Failed:    types.ProvisionStatus.Failed,
	types.OrderStatusHostingAPI.Completed: types.ProvisionStatus.Completed,
}

// HostingOrderDetailsResponseHandler This is a callback handler for the hosting order details response event
// received from AWS  SQS
func (service *WorkerService) HostingOrderDetailsResponseHandler(server sqs.Server, message proto.Message) error {

	ctx := server.Ctx

	orderDetails := message.(*hostingproto.OrderDetailsResponse)

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.LogID: uuid.NewString(),
	})

	logger.Debug("Received hosting order details response", log.Fields{
		"external_order_id": orderDetails.Id,
		"status":            orderDetails.Status,
		"is_active":         orderDetails.IsActive,
		"is_deleted":        orderDetails.IsDeleted,
	})

	var hostingStatusID *string
	if id := service.db.GetHostingStatusId(orderDetails.Status); id != "" {
		hostingStatusID = &id
	} else {
		log.Warn("unknown status received", log.Fields{"external_order_id": orderDetails.Id, "status": orderDetails.Status})
	}

	upd := &model.ProvisionHostingCreate{
		IsActive:        orderDetails.IsActive,
		IsDeleted:       orderDetails.IsDeleted,
		HostingStatusID: hostingStatusID,
		StatusID:        service.db.GetProvisionStatusId(orderStatusToProvisionHostingCreateStatus[orderDetails.Status]),
	}

	where := &model.ProvisionHostingCreate{
		ExternalOrderID: types.ToPointer(orderDetails.Id),
		StatusID:        service.db.GetProvisionStatusId(types.ProvisionStatus.PendingAction),
	}

	err := service.db.UpdateProvisionHostingCreate(ctx, upd, where)
	if errors.Is(err, database.ErrNotFound) {
		logger.Warn("No matching provision hosting create record found for pending_action")
		// temporary solution to fix TDP-4286
		hosting, err := service.db.GetHosting(ctx, &model.Hosting{ExternalOrderID: &orderDetails.Id})
		if err != nil {
			if errors.Is(err, database.ErrNotFound) {
				log.Warn("unknown external order id", log.Fields{"external_order_id": orderDetails.Id})
				return nil
			}

			log.Error("error getting hosting by external order id",
				log.Fields{
					"external_order_id": orderDetails.Id,
					"error":             err,
				},
			)
			return nil
		}

		hosting.HostingStatusID = hostingStatusID
		hosting.IsActive = orderDetails.IsActive
		hosting.IsDeleted = orderDetails.IsDeleted
		hosting.StatusReason = types.ToPointer(orderDetails.StatusDetails)

		err = service.db.UpdateHosting(ctx, hosting)
		if err != nil {
			log.Error("error updating hosting with status",
				log.Fields{
					"hosting_id": hosting.ID,
					"status":     orderDetails.Status,
					"error":      err,
				},
			)
			return nil
		}

		log.Info("hosting order is successfully updated",
			log.Fields{
				"external_order_id": orderDetails.Id,
				"status":            orderDetails.Status,
			},
		)

		return nil
	}

	if err != nil {
		logger.Error("Error updating provision hosting create record", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return err
	}

	logger.Info("Successfully updated provision hosting create record", log.Fields{
		"status":     orderDetails.Status,
		"is_active":  orderDetails.IsActive,
		"is_deleted": orderDetails.IsDeleted,
	})

	return nil

}
