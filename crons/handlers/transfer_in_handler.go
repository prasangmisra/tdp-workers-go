package handlers

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	rymessages "github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	message_bus "github.com/tucowsinc/tdp-workers-go/pkg/message_bus"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

const DefaultPendingTransferInBatchSize = 100

// ProcessPendingTransferInRequestMessage converts database transfer in request message into transfer query request message
func (s *CronService) ProcessPendingTransferInRequestMessage(ctx context.Context) error {
	// Use a single logger for the cron job
	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CronType: "ProcessPendingTransferInRequestsCron",
		types.LogFieldKeys.LogID:    uuid.NewString(),
	})

	logger.Info("Starting processing of pending transfer in requests")

	pendingTransferIns, err := s.db.GetExpiredPendingProvisionDomainTransferInRequests(ctx, DefaultPendingTransferInBatchSize)
	if err != nil {
		logger.Error(types.LogMessages.FetchJobByIDFromDBFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return fmt.Errorf("error getting pending transfer in requests: %w", err)
	}

	logger.Info("Fetched expired pending transfer in requests", log.Fields{
		"count": len(pendingTransferIns),
	})
	if len(pendingTransferIns) == 0 {
		log.Info("No pending transfer in requests to process")
		return nil
	}

	for _, tn := range pendingTransferIns {
		// Add transfer-specific context to the log
		logger.Info("Processing pending transfer", log.Fields{
			types.LogFieldKeys.Domain: tn.DomainName,
			types.LogFieldKeys.JobID:  tn.ID,
		})

		if err := s.processPendingTransfer(ctx, &tn, logger); err != nil {
			logger.Error("Error processing transfer", log.Fields{
				types.LogFieldKeys.Domain: tn.DomainName,
				types.LogFieldKeys.JobID:  tn.ID,
				types.LogFieldKeys.Error:  err,
			})
			// Consider whether to continue processing other transfers or return here
		}
	}

	log.Info("Done processing pending transfer in requests", log.Fields{"requests": len(pendingTransferIns)})

	return nil
}

func (s *CronService) processPendingTransfer(ctx context.Context, tn *model.ProvisionDomainTransferInRequest, logger logger.ILogger) error {
	logger.Info("Processing pending transfer")

	acc, err := s.db.GetAccreditationById(ctx, tn.AccreditationID)
	if err != nil {
		logger.Error("Error fetching accreditation", log.Fields{
			types.LogFieldKeys.AccreditationID: tn.AccreditationID,
			types.LogFieldKeys.Error:           err,
		})
		return fmt.Errorf("error getting accreditation by id: %w", err)
	}

	logger.Info("Sending transfer query request to registry")
	transferQueryMsg := &rymessages.DomainTransferQueryRequest{
		Name: tn.DomainName,
		Pw:   tn.Pw,
	}

	response, err := message_bus.Call(ctx, s.bus, types.GetTransformQueue(acc.Name), transferQueryMsg)
	if err != nil {
		logger.Error("Error sending transfer query request", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return err
	}

	logger.Info("Received response from registry")
	switch m := response.(type) {
	case *rymessages.DomainTransferResponse:
		return s.handleTransferInResponse(ctx, tn, m, acc, logger)
	default:
		logger.Error("Unexpected message type received", log.Fields{
			"message_type": fmt.Sprintf("%T", m),
		})
		return fmt.Errorf("unexpected message type received for domain transfer in query response: %T", m)
	}
}

func (s *CronService) handleTransferInResponse(ctx context.Context, tn *model.ProvisionDomainTransferInRequest, msg *rymessages.DomainTransferResponse, acc *model.Accreditation, logger logger.ILogger) error {
	logger.Info("Handling transfer in response", log.Fields{
		types.LogFieldKeys.EppCode: msg.GetRegistryResponse().GetEppCode(),
	})

	switch msg.GetRegistryResponse().GetEppCode() {
	case types.EppCode.Success:
		return s.processSuccessfulTransferInResponse(ctx, tn, msg, acc, logger)
	case types.EppCode.NotPendingTransfer:
		return s.processNotPendingTransferInResponse(ctx, tn, msg, acc, logger)
	default:
		logger.Error("Unexpected EPP code in registry response", log.Fields{
			types.LogFieldKeys.EppCode: msg.GetRegistryResponse().GetEppCode(),
		})
		return fmt.Errorf("unexpected registry response EPP code: %v", msg.GetRegistryResponse().GetEppCode())

	}
}

func (s *CronService) processSuccessfulTransferInResponse(ctx context.Context, tn *model.ProvisionDomainTransferInRequest, msg *rymessages.DomainTransferResponse, acc *model.Accreditation, logger logger.ILogger) error {
	logger.Info("Processing successful transfer in response", log.Fields{
		types.LogFieldKeys.Status: msg.GetStatus(),
	})

	requestStatus := msg.GetStatus()

	if requestStatus == types.TransferStatus.Pending {

		if acc.RegistrarID != msg.RequestedBy {
			// check domain info if transfer request is not requested by us
			logger.Info("Transfer request not initiated by current registrar. Checking domain info")
			return s.processPendingTransferIn(ctx, tn, msg, acc, logger)
		}

		// still pending and still ours skip
		// TODO: implement a skipping mechanism?
		logger.Info("Transfer is still pending and initiated by current registrar. Skipping further processing.")
		return nil
	}

	transferStatusId := s.db.GetTransferStatusId(requestStatus)
	if transferStatusId == "" {
		logger.Error("Unexpected transfer status", log.Fields{
			types.LogFieldKeys.Status: msg.Status,
		})
		return fmt.Errorf("unexpected transfer status: %s", msg.Status)
	}

	return s.processTransferInWithStatus(ctx, tn, msg, acc, logger)
}

func (s *CronService) processNotPendingTransferInResponse(ctx context.Context, tn *model.ProvisionDomainTransferInRequest, msg *rymessages.DomainTransferResponse, acc *model.Accreditation, logger logger.ILogger) error {
	logger.Info("Processing not-pending transfer in response")
	return s.processPendingTransferIn(ctx, tn, msg, acc, logger)
}

func (s *CronService) processPendingTransferIn(ctx context.Context, tn *model.ProvisionDomainTransferInRequest, msg *rymessages.DomainTransferResponse, acc *model.Accreditation, logger logger.ILogger) error {
	logger.Info("Fetching domain info to determine ownership")
	domainInfoResp, err := s.getDomainInfo(ctx, msg.Name, acc)
	if err != nil {
		logger.Error("Error fetching domain info", log.Fields{
			types.LogFieldKeys.Domain: msg.Name,
			types.LogFieldKeys.Error:  err,
		})
		return err
	}

	if domainInfoResp.GetRegistryResponse().GetEppCode() != types.EppCode.Success {
		logger.Error("Error getting domain info from registry", log.Fields{
			types.LogFieldKeys.Domain: msg.Name,
			types.LogFieldKeys.Error:  err,
		})
		return fmt.Errorf(
			"error getting domain info from registry for domain[%s]: %s",
			msg.Name,
			domainInfoResp.GetRegistryResponse().GetEppMessage(),
		)
	}

	transferStatus := types.TransferStatus.ClientRejected
	// if we own the domain then transfer was approved, else it was rejected
	if acc.RegistrarID == domainInfoResp.Clid {
		transferStatus = types.TransferStatus.ClientApproved
	}

	logger.Info("Updating transfer request with final status", log.Fields{
		types.LogFieldKeys.Status: transferStatus,
	})
	return s.updateTransferRequest(ctx, tn, types.ProvisionStatus.Completed, transferStatus, logger)
}

func (s *CronService) processTransferInWithStatus(ctx context.Context, tn *model.ProvisionDomainTransferInRequest, msg *rymessages.DomainTransferResponse, acc *model.Accreditation, logger logger.ILogger) error {
	logger.Info("Processing transfer in with status", log.Fields{
		types.LogFieldKeys.Status: msg.GetStatus(),
	})

	transferStatus := msg.GetStatus()

	// check domain info if transfer request is not requested by us
	if acc.RegistrarID != msg.RequestedBy {
		domainInfoResp, err := s.getDomainInfo(ctx, msg.Name, acc)
		if err != nil {
			logger.Error("Error fetching domain info for ownership check", log.Fields{
				types.LogFieldKeys.Domain: msg.Name,
				types.LogFieldKeys.Error:  err,
			})
			return err
		}

		if domainInfoResp.GetRegistryResponse().GetEppCode() != types.EppCode.Success {
			logger.Error("Error getting domain info from registry for ownership check", log.Fields{
				types.LogFieldKeys.Domain: msg.Name,
				types.LogFieldKeys.Error:  err,
			})
			return fmt.Errorf(
				"error getting domain info from registry for ownership check [%s]: %s",
				msg.Name,
				domainInfoResp.GetRegistryResponse().GetEppMessage(),
			)
		}

		transferStatus = types.TransferStatus.ClientRejected
		// if we own the domain then transfer was approved, else it was rejected
		if acc.RegistrarID == domainInfoResp.Clid {
			transferStatus = types.TransferStatus.ClientApproved
		}
	}

	return s.updateTransferRequest(ctx, tn, types.ProvisionStatus.Completed, transferStatus, logger)
}

func (s *CronService) updateTransferRequest(ctx context.Context, tn *model.ProvisionDomainTransferInRequest, statusID string, transferStatusID string, logger logger.ILogger) error {
	logger.Info("Updating transfer request status in database", log.Fields{
		types.LogFieldKeys.JobID:  tn.ID,
		types.LogFieldKeys.Status: fmt.Sprintf("Provision: %s, Transfer: %s", statusID, transferStatusID),
	})

	tn.StatusID = s.db.GetProvisionStatusId(statusID)
	tn.TransferStatusID = s.db.GetTransferStatusId(transferStatusID)

	if err := s.db.UpdateProvisionDomainTransferInRequest(ctx, tn); err != nil {
		logger.Error("Error updating transfer request", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return fmt.Errorf("error setting transfer in request status: %w", err)
	}
	return nil
}
