package handlers

import (
	"context"
	"fmt"
	"strconv"

	"github.com/google/uuid"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

const DefaultTransferAwayOrdersBatchSize = 100

func (s *CronService) ProcessTransferAwayOrders(ctx context.Context) error {
	// Use a single logger for the entire cron job
	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CronType: "ProcessTransferAwayOrdersCron",
		types.LogFieldKeys.LogID:    uuid.NewString(),
	})

	logger.Info("Starting processing of transfer away orders")

	orders, err := s.db.GetActionableTransferAwayOrders(ctx, DefaultTransferAwayOrdersBatchSize)
	if err != nil {
		logger.Error("Failed to get actionable transfer away orders", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return fmt.Errorf("failed to get actionable transfer away orders: %w", err)
	}

	logger.Info("Fetched actionable transfer away orders", log.Fields{
		"order_count": len(orders),
	})
	if len(orders) == 0 {
		log.Info("No transfer away orders to process")
		return nil
	}

	for _, order := range orders {
		logger.Info("Processing transfer away order", log.Fields{
			types.LogFieldKeys.OrderID: order.OrderID,
			types.LogFieldKeys.Domain:  order.DomainName,
		})

		if err = s.processTransferAwayOrder(ctx, order, logger); err != nil {
			logger.Error("Error processing transfer away order", log.Fields{
				types.LogFieldKeys.OrderID: order.OrderID,
				types.LogFieldKeys.Domain:  order.DomainName,
				types.LogFieldKeys.Error:   err,
			})
		}
	}

	log.Info("Done processing transfer away orders", log.Fields{"orders": len(orders)})

	return nil
}

func (s *CronService) processTransferAwayOrder(ctx context.Context, order model.VOrderTransferAwayDomain, logger logger.ILogger) error {
	logger.Info("Processing transfer away order")
	acc, err := s.db.GetAccreditationById(ctx, order.AccreditationID)
	if err != nil {
		logger.Error("Error getting accreditation by ID", log.Fields{
			types.LogFieldKeys.AccreditationID: order.AccreditationID,
			types.LogFieldKeys.Error:           err,
		})
		return fmt.Errorf("error getting accreditation by id: %w", err)
	}

	domainInfoResp, err := s.getDomainInfo(ctx, order.DomainName, acc)
	if err != nil {
		logger.Error("Error getting domain info", log.Fields{
			types.LogFieldKeys.Domain: order.DomainName,
			types.LogFieldKeys.Error:  err,
		})
		return fmt.Errorf("error getting domain info for domain[%s]: %w", order.DomainName, err)
	}

	if domainInfoResp.GetRegistryResponse().GetEppCode() != types.EppCode.Success {
		logger.Error("Error getting domain info from registry", log.Fields{
			types.LogFieldKeys.Domain: order.DomainName,
			types.LogFieldKeys.Error:  err,
		})
		return fmt.Errorf(
			"error getting domain info from registry for domain[%s]: %s",
			order.DomainName,
			domainInfoResp.GetRegistryResponse().GetEppMessage(),
		)
	}

	if acc.RegistrarID != domainInfoResp.Clid {
		logger.Info("Domain not owned by current registrar. Marking transfer as server-approved")
		return s.markTransferServerApproved(ctx, order, logger)
	}

	// we own the domain
	logger.Info("Domain owned by current registrar. Handling pending transfer")
	return s.handlePendingTransfer(ctx, order, logger)
}

func (s *CronService) markTransferServerApproved(ctx context.Context, order model.VOrderTransferAwayDomain, logger logger.ILogger) error {
	if err := s.updateTransferStatus(ctx, order.OrderItemID, types.TransferStatus.ServerApproved); err != nil {
		logger.Error("Failed to update transfer status", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return fmt.Errorf("failed to update transfer status for order[%v]: %w", order.OrderID, err)
	}
	return s.db.OrderNextStatus(ctx, order.OrderID, true)
}

func (s *CronService) handlePendingTransfer(ctx context.Context, order model.VOrderTransferAwayDomain, logger logger.ILogger) error {
	tldSettings, err := s.db.GetTLDSetting(ctx, order.AccreditationTldID, "tld.lifecycle.transfer_server_auto_approve_supported")
	if err != nil {
		logger.Error("Failed to get TLD setting", log.Fields{
			types.LogFieldKeys.AccreditationID: order.AccreditationTldID,
			types.LogFieldKeys.Error:           err,
		})
		return fmt.Errorf("failed to get TLD setting: %w", err)
	}

	isTransferServerAutoApproveSupported, err := strconv.ParseBool(tldSettings.Value)
	if err != nil {
		logger.Error("Failed to parse auto-transfer approval setting", log.Fields{
			"setting_value":          tldSettings.Value,
			types.LogFieldKeys.Error: err,
		})
		return fmt.Errorf("failed to parse auto-transfer approval setting: %w", err)
	}

	if isTransferServerAutoApproveSupported {
		// Do nothing, wait for registry approval
		logger.Info("Transfer server auto-approve is supported. No action required")
		return nil
	}

	logger.Info("Transfer server auto-approve not supported. Marking transfer as client-approved")
	return s.markTransferClientApproved(ctx, order, logger)
}

func (s *CronService) markTransferClientApproved(ctx context.Context, order model.VOrderTransferAwayDomain, logger logger.ILogger) error {
	if err := s.updateTransferStatus(ctx, order.OrderItemID, types.TransferStatus.ClientApproved); err != nil {
		logger.Error("Failed to update transfer status", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return fmt.Errorf("failed to update transfer status for order[%v]: %w", order.OrderID, err)
	}
	return s.db.OrderNextStatus(ctx, order.OrderID, true)
}

func (s *CronService) updateTransferStatus(ctx context.Context, orderItemID string, status string) error {
	return s.db.UpdateTransferAwayDomain(ctx, &model.OrderItemTransferAwayDomain{
		ID:               &orderItemID,
		TransferStatusID: s.db.GetTransferStatusId(status),
	})
}
