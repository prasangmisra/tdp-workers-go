package handlers

import (
	"fmt"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
	"google.golang.org/protobuf/proto"
)

func (service *WorkerService) HandlerRouter(s messagebus.Server, m proto.Message) (err error) {

	// we need to type-cast the proto.Message to the wanted type
	request := m.(*job.Notification)

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.Message: request.String(),
	})

	logger.Info("Routing job to appropriate handler")

	switch request.Type {
	case "provision_contact_create":
		return service.ContactProvisionHandler(s, m)
	case "provision_domain_contact_update":
		return service.ContactUpdateHandler(s, m)
	case "provision_contact_delete":
		return service.ContactDeleteHandler(s, m)
	}

	err = fmt.Errorf("no handlers for type: %s", request.Type)

	logger.Error("No handler found for job type", log.Fields{
		types.LogFieldKeys.Error: err,
	})

	return
}
