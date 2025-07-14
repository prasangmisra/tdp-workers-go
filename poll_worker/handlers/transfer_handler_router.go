package handlers

import (
	"context"
	"fmt"

	"github.com/tucowsinc/tdp-shared-go/logger"

	"github.com/tucowsinc/tdp-messages-go/message/worker"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

type TransferHandler struct{}

func NewTransferHandler() *TransferHandler {
	return &TransferHandler{}
}

func (a *TransferHandler) Matches(msg *worker.PollMessage) bool {
	return msg.Type == PollMessageType.Transfer
}

func (a *TransferHandler) Handle(ctx context.Context, service *WorkerService, request *worker.PollMessage, logger logger.ILogger) (err error) {
	data := request.GetTrnData()
	if data == nil {
		logger.Error("Missing transfer data in poll message")
		return fmt.Errorf("missing transfer data in poll message with ID: %s", request.Id)
	}

	acc, err := service.getAccreditation.WithCache(request.Accreditation, func() (*model.Accreditation, error) {
		return service.db.GetAccreditationByName(ctx, request.Accreditation)
	})
	if err != nil {
		logger.Error("Unknown accreditation in poll message", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	if data.RequestedBy == nil {
		logger.Error("Missing transfer request", log.Fields{
			types.LogFieldKeys.RequestID: request.Id,
			LogFieldKeys.Accreditation:   request.Accreditation,
		})
		return fmt.Errorf("missing transfer request details for poll message ID: %s", request.Id)
	}

	if *data.RequestedBy == acc.RegistrarID {
		err = service.handlerTransferInRequest(ctx, data, acc)
		if err != nil {
			logger.Error("Error handling transfer_in request", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return fmt.Errorf("error handling transfer_in request for poll message ID: %s: %w", request.Id, err)
		}
	} else {
		err = service.handlerTransferAwayRequest(ctx, data, acc)
		if err != nil {
			logger.Error("Error handling transfer_away request", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return fmt.Errorf("error handling transfer_away request for poll message ID: %s: %w", request.Id, err)
		}
	}

	logger.Debug("Poll message handled successfully for domain transfer", log.Fields{
		types.LogFieldKeys.RequestID: request.Id,
		LogFieldKeys.Accreditation:   request.Accreditation,
		types.LogFieldKeys.Domain:    data.Name,
		types.LogFieldKeys.Status:    data.Status,
	})

	return
}
