package handlers

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

func (service *WorkerService) handlerTransferInRequest(ctx context.Context, request *ryinterface.EppPollTrnData, acc *model.Accreditation) (err error) {
	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.LogID:  uuid.NewString(),
		types.LogFieldKeys.Domain: request.GetName(),
	})

	transferData, err := service.db.GetProvisionDomainTransferInRequest(ctx, &model.ProvisionDomainTransferInRequest{
		DomainName: request.GetName(),
		StatusID:   service.db.GetProvisionStatusId(types.ProvisionStatus.PendingAction),
	})
	if err != nil {
		if errors.Is(err, database.ErrNotFound) {
			logger.Warn("Transfer_in request not found for domain with pending action status")
			return nil
		}

		logger.Error("Error fetching provision transfer_in request for domain", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}
	requestStatus := request.GetStatus()
	if requestStatus == TransferStatus.Pending {
		logger.Debug("Transfer status is pending, no action required")
		return // no need to update the status
	}

	if requestStatus == TransferStatus.ServerApproved {
		domain, dbErr := service.db.GetDomainAccreditation(context.Background(), request.GetName())
		if dbErr == nil && domain != nil {
			if domain.Accreditation.ID != acc.ID {
				return fmt.Errorf("%w: domain %s still exists. Deferring `serverApproved` transfer-in handling."+
					" Waiting for transfer-away completion to delete this domain", ErrDeferMessage, request.GetName())
			}
			return fmt.Errorf("domain [%s] is allready transferred", request.GetName())
		}
	}

	transferStatusId := service.db.GetTransferStatusId(requestStatus)
	if transferStatusId == "" {
		logger.Error("Invalid transfer status", log.Fields{
			types.LogFieldKeys.Status: requestStatus,
			types.LogFieldKeys.Error:  err,
		})
		return fmt.Errorf("invalid transfer status %s", requestStatus)
	}

	logger.Info("Processing transfer_in request", log.Fields{
		types.LogFieldKeys.Status: requestStatus,
	})
	err = service.db.UpdateProvisionDomainTransferInRequest(ctx, &model.ProvisionDomainTransferInRequest{
		ID:               transferData.ID,
		StatusID:         service.db.GetProvisionStatusId(types.ProvisionStatus.Completed),
		TransferStatusID: transferStatusId,
	})

	if err != nil {
		logger.Error("Error updating provision status for transfer_in request", log.Fields{
			types.LogFieldKeys.Error: err,
			types.LogFieldKeys.JobID: transferData.ID,
		})
		return
	}

	logger.Info("Transfer_in request processed successfully")
	return

}
