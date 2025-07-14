package handlers

import (
	"fmt"

	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/job"
)

func (service *WorkerService) HandlerRouter(s messagebus.Server, m proto.Message) (err error) {
	provisionHandler := service.HostProvisionHandler
	updateHandler := service.HostUpdateHandler
	deleteHandler := service.HostDeleteHandler
	validateHandler := service.ValidateHostAvailableHandler

	// we need to type-cast the proto.Message to the wanted type
	request := m.(*job.Notification)

	switch request.Type {
	case "provision_host_create":
		return provisionHandler(s, m)
	case "provision_host_update":
		return updateHandler(s, m)
	case "provision_host_delete", "provision_domain_delete_host":
		return deleteHandler(s, m)
	case "validate_host_available":
		return validateHandler(s, m)
	}

	err = fmt.Errorf("no handlers for type: %s", request.Type)

	return
}
