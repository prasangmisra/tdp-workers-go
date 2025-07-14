package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"google.golang.org/protobuf/types/known/anypb"

	"github.com/alexliesenfeld/health"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message"
	rymessages "github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	mb "github.com/tucowsinc/tdp-workers-go/pkg/message_bus"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

type WorkerService struct {
	db     database.Database
	bus    messagebus.MessageBus
	tracer *oteltrace.Tracer
}

func NewWorkerService(bus messagebus.MessageBus, db database.Database, tracer *oteltrace.Tracer) *WorkerService {
	return &WorkerService{
		db:     db,
		bus:    bus,
		tracer: tracer,
	}
}

// RegisterHandlers registers the handlers for the service.
func (s *WorkerService) RegisterHandlers() {
	s.bus.Register(
		&rymessages.DomainCreateResponse{},
		s.RyDomainProvisionHandler,
	)

	s.bus.Register(
		&rymessages.DomainRenewResponse{},
		s.RyDomainRenewHandler,
	)

	s.bus.Register(
		&rymessages.DomainUpdateResponse{},
		s.RyDomainUpdateRouter,
	)

	s.bus.Register(
		&rymessages.DomainDeleteResponse{},
		s.RyDomainDeleteHandler,
	)

	s.bus.Register(
		&rymessages.DomainCheckResponse{},
		s.RyDomainCheckHandler,
	)

	s.bus.Register(
		&rymessages.DomainTransferResponse{},
		s.RyDomainTransferRouter,
	)

	s.bus.Register(
		&rymessages.DomainInfoResponse{},
		s.RyDomainInfoRouter,
	)

	s.bus.Register(
		&message.ErrorResponse{},
		s.RyErrorResponseRouter(),
	)
}

// HealthChecks returns a slice of health checks for the service.
func (s *WorkerService) HealthChecks(cfg config.Config) (checks []health.Check) {
	return []health.Check{
		database.HealthCheck(s.db),
		mb.HealthCheck(cfg.RmqUrl()),
	}
}

// createTransferAwayOrder creates transfer away order with serverApproved status
func createTransferAwayOrder(ctx context.Context, tx database.Database, data *types.DomainTransferAwayData, domainInfoResp *rymessages.DomainInfoResponse) (err error) {
	order := &model.Order{
		TypeID:           tx.GetOrderTypeId("transfer_away", "domain"),
		TenantCustomerID: data.TenantCustomerId,
		OrderItemTransferAwayDomain: model.OrderItemTransferAwayDomain{
			Name:             data.Name,
			TransferStatusID: tx.GetTransferStatusId(types.TransferStatus.ServerApproved),
			RequestedBy:      domainInfoResp.Clid,
			RequestedDate:    time.Now(),
			ActionBy:         data.Accreditation.RegistrarID,
			ActionDate:       time.Now(),
			ExpiryDate:       time.Now(),
		},
	}

	// Include info in transfer order metadata regarding the original order which caused this order creation
	metadata := &map[string]interface{}{
		"internal":      true,
		"orig_order_id": data.Metadata["order_id"],
		"reason":        fmt.Sprintf("domain is no longer sponsored by registrar '%s'", data.Accreditation.RegistrarID),
	}
	metadataBytes, err := json.Marshal(metadata)
	if err != nil {
		return fmt.Errorf("failed to marshal metadata: %w", err)
	}
	order.Metadata = types.ToPointer(string(metadataBytes))

	err = tx.TransferAwayDomainOrder(ctx, order)
	if err != nil {
		return fmt.Errorf("error creating transfer away domain order: %w", err)
	}

	// Update order status to `processing`
	err = tx.OrderNextStatus(ctx, order.ID, true)
	if err != nil {
		return fmt.Errorf("failed to update order status: %w", err)
	}

	return
}

func (service *WorkerService) getDomainInfo(ctx context.Context, domainName string, accName string) (*rymessages.DomainInfoResponse, error) {
	domainInfoMsg := &rymessages.DomainInfoRequest{Name: domainName}
	response, err := mb.Call(ctx, service.bus, types.GetTransformQueue(accName), domainInfoMsg)
	if err != nil {
		return nil, err
	}

	domainInfoResp, ok := response.(*rymessages.DomainInfoResponse)
	if !ok {
		return nil, fmt.Errorf("unexpected message type received for domain info response: %T", response)
	}

	return domainInfoResp, nil
}

// rgpStatusExists checks if the RGP extension exists in the response
func rgpStatusExists(extensions map[string]*anypb.Any) bool {
	if rgpExt, ok := extensions["rgp"]; ok {
		return rgpExt != nil
	}
	return false
}

// handleRgpExtension handles the RGP extension in the response
func handleRgpExtension(extensions map[string]*anypb.Any) (*extension.RgpInfoResponse, error) {
	rgpMsg := new(extension.RgpInfoResponse)
	if rgpStatusExists(extensions) {
		if err := extensions["rgp"].UnmarshalTo(rgpMsg); err != nil {
			return nil, err
		}
	}

	return rgpMsg, nil
}

// getTransferInfo retrieves the transfer information for a domain from registry
func (service *WorkerService) getTransferInfo(ctx context.Context, domainName string, pw *string, accName string) (*rymessages.DomainTransferResponse, error) {
	transferQueryMsg := &rymessages.DomainTransferQueryRequest{
		Name: domainName,
		Pw:   pw,
	}

	response, err := mb.Call(ctx, service.bus, types.GetTransformQueue(accName), transferQueryMsg)
	if err != nil {
		return nil, err
	}

	transferQueryResp, ok := response.(*rymessages.DomainTransferResponse)
	if !ok {
		return nil, fmt.Errorf("unexpected message type received for domain transfer query response: %T", response)
	}

	return transferQueryResp, nil
}
