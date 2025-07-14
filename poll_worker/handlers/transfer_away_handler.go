package handlers

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

func (service *WorkerService) handlerTransferAwayRequest(ctx context.Context, request *ryinterface.EppPollTrnData, acc *model.Accreditation) (err error) {

	requestStatus := request.GetStatus()
	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.LogID:  uuid.NewString(),
		types.LogFieldKeys.Domain: request.GetName(),
		types.LogFieldKeys.Status: requestStatus,
	})
	logger.Info("Handling transfer away request")

	switch requestStatus {
	case TransferStatus.Pending:
		err = service.handlePendingTransfer(ctx, request, acc, logger)
		if err != nil {
			logger.Error("Error handling pending transfer request", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return err
		}

	case TransferStatus.ServerApproved:
		err = service.handleServerApprovedTransfer(ctx, request, acc, logger)
		if err != nil {
			logger.Error("Error handling server-approved transfer request", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return err
		}
	case TransferStatus.ClientCancelled, TransferStatus.ServerCancelled:
		err = service.cancelledTransfer(ctx, request, acc)
		if err != nil {
			return err
		}

	default:
		logger.Warn("Unexpected transfer status")
		return nil
	}

	logger.Debug("Handler transfer away request completed successfully")
	return nil
}

func (service *WorkerService) handlePendingTransfer(ctx context.Context, request *ryinterface.EppPollTrnData, acc *model.Accreditation, logger logger.ILogger) (err error) {
	_, err = service.createOrderItemTransferAwayDomain(ctx, request, acc, logger)
	if err != nil {
		return fmt.Errorf("error handling pending transfer away order domain [%v]: %w", request.GetName(), err)
	}

	return
}

func (service *WorkerService) handleServerApprovedTransfer(ctx context.Context, request *ryinterface.EppPollTrnData, acc *model.Accreditation, logger logger.ILogger) (err error) {
	transferAwayOrder, err := service.db.GetTransferAwayOrder(ctx, types.OrderStatusEnum.Created, request.GetName(), acc.TenantID)
	var orderID *string

	if err != nil {
		if !errors.Is(err, database.ErrNotFound) {
			return fmt.Errorf("error getting transfer away order for domain[%v] with ServerApproved status: %w", request.GetName(), err)
		}

		orderID, err = service.createOrderItemTransferAwayDomain(ctx, request, acc, logger)
		if err != nil {
			return fmt.Errorf("error creating transfer away order for domain[%v] with ServerApproved status: %w", request.GetName(), err)
		}
	} else {
		err = service.db.UpdateTransferAwayDomain(ctx, &model.OrderItemTransferAwayDomain{
			ID:               transferAwayOrder.ID,
			TransferStatusID: service.db.GetTransferStatusId(TransferStatus.ServerApproved),
		})

		if err != nil {
			return fmt.Errorf("error updating transfer away order for domain[%v] with ServerApproved status: %w", request.GetName(), err)
		}

		orderID = &transferAwayOrder.OrderID
	}

	// Update order status to `processing`
	err = service.db.OrderNextStatus(ctx, *orderID, true)
	if err != nil {
		return fmt.Errorf("failed to update order status: %w", err)
	}

	return
}

func (service *WorkerService) cancelledTransfer(ctx context.Context, request *ryinterface.EppPollTrnData, acc *model.Accreditation) (err error) {
	transferAwayOrder, err := service.db.GetTransferAwayOrder(ctx, types.OrderStatusEnum.Created, request.GetName(), acc.TenantID)

	if err != nil {
		if errors.Is(err, database.ErrNotFound) {
			return fmt.Errorf("%w: transfer away order for domain %s does not exist."+
				" Deferring clientCancelled transfer-away handling", ErrDeferMessage, request.GetName())
		}
		return fmt.Errorf("error getting transfer away order for domain[%v] with ClientCancelled status: %w", request.GetName(), err)
	}

	err = service.db.UpdateTransferAwayDomain(ctx, &model.OrderItemTransferAwayDomain{
		ID:               transferAwayOrder.ID,
		TransferStatusID: service.db.GetTransferStatusId(request.GetStatus()),
	})

	if err != nil {
		return fmt.Errorf("error updating transfer away order for domain[%v] with ClientCancelled status: %w", request.GetName(), err)
	}

	// Update order status to `failed` for ClientCancelled and 'ServerCancelled'
	err = service.db.OrderNextStatus(ctx, transferAwayOrder.OrderID, false)
	if err != nil {
		return fmt.Errorf("failed to update order status: %w", err)
	}

	return
}

func (service *WorkerService) createOrderItemTransferAwayDomain(ctx context.Context, request *ryinterface.EppPollTrnData, acc *model.Accreditation, logger logger.ILogger) (*string, error) {
	domain, err := service.db.GetDomainAccreditation(ctx, request.GetName())
	if err != nil {
		return nil, fmt.Errorf("error getting domain[%v]: %w", request.GetName(), err)
	}

	if domain.Accreditation.ID != acc.ID || request.GetActionBy() != domain.Accreditation.RegistrarID {
		return nil, fmt.Errorf("domain[%v] is not owned by the registrar[%v]", request.GetName(), acc.Name)
	}

	order := &model.Order{
		TypeID:           service.db.GetOrderTypeId("transfer_away", "domain"),
		TenantCustomerID: domain.TenantCustomerID,
		OrderItemTransferAwayDomain: model.OrderItemTransferAwayDomain{
			Name:             request.GetName(),
			TransferStatusID: service.db.GetTransferStatusId(request.GetStatus()),
			RequestedBy:      request.GetRequestedBy(),
			RequestedDate:    request.GetRequestedDate().AsTime(),
			ActionBy:         request.GetActionBy(),
			ActionDate:       request.ActionDate.AsTime(),
			ExpiryDate:       request.ExpiryDate.AsTime(),
		},
	}

	err = service.db.TransferAwayDomainOrder(ctx, order)
	if err != nil {
		if errors.Is(err, database.ErrNotFound) {
			logger.Info("Domain not found, skipping transfer away request",
				log.Fields{types.LogFieldKeys.Domain: request.GetName()})
			return nil, nil
		}

		return nil, fmt.Errorf("error creating transfer away domain order: %w", err)
	}

	return &order.ID, nil
}
