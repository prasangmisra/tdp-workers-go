package handlers

import (
	"fmt"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	"google.golang.org/protobuf/proto"
)

func (service *WorkerService) HandlerRouter(s messagebus.Server, m proto.Message) (err error) {
	// we need to type-cast the proto.Message to the wanted type
	request := m.(*job.Notification)

	switch request.Type {
	case "provision_hosting_create":
		return service.HostingProvisionHandler(s, m)
	case "provision_hosting_update":
		return service.HostingUpdateHandler(s, m)
	case "provision_hosting_delete":
		return service.HostingDeleteHandler(s, m)
	case "provision_hosting_certificate_create":
		return service.HostingCertificateProvisionHandler(s, m)
	case "provision_hosting_dns_check":
		return service.DNSCheckHandler(s, m)

	}

	err = fmt.Errorf("no handlers for type: %s", request.Type)

	return
}
