package handlers

import (
	"fmt"

	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/job"
)

func (service *WorkerService) HandlerRouter(s messagebus.Server, m proto.Message) (err error) {
	infoHandler := service.DomainInfoHandler
	provisionHandler := service.DomainProvisionHandler
	renewHandler := service.DomainRenewHandler
	redeemHandler := service.DomainRedeemHandler
	redeemReportHandler := service.DomainRedeemReportHandler
	deleteHandler := service.DomainDeleteHandler
	updateHandler := service.DomainUpdateHandler
	validateCheckHandler := service.ValidateDomainCheckHandler
	validateClaimsHandler := service.ValidateDomainClaimsCheckHandler
	transferInRequestHandler := service.DomainTransferInRequestHandler
	transferActionHandler := service.DomainTransferActionHandler

	// we need to type-cast the proto.Message to the wanted type
	request := m.(*job.Notification)

	switch request.Type {
	case "provision_domain_create":
		return provisionHandler(s, m)
	case "provision_domain_renew":
		return renewHandler(s, m)
	case "provision_domain_redeem":
		return redeemHandler(s, m)
	case "provision_domain_redeem_report":
		return redeemReportHandler(s, m)
	case "provision_domain_delete":
		return deleteHandler(s, m)
	case "provision_domain_update":
		return updateHandler(s, m)
	case "validate_domain_available", "validate_domain_premium":
		return validateCheckHandler(s, m)
	case "validate_domain_claims":
		return validateClaimsHandler(s, m)
	case "provision_domain_transfer_in_request":
		return transferInRequestHandler(s, m)
	case "provision_domain_transfer_away", "provision_domain_transfer_in_cancel_request":
		return transferActionHandler(s, m)
	case "provision_domain_transfer_in", "validate_domain_transferable", "provision_domain_expiry_date_check", "setup_domain_renew", "setup_domain_delete":
		return infoHandler(s, m)
	}

	err = fmt.Errorf("no handlers for type: %s", request.Type)

	return
}
