package handlers

import (
	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	tcwire "github.com/tucowsinc/tdp-messages-go/message"
	defaulthandlers "github.com/tucowsinc/tdp-workers-go/pkg/handlers"
)

// RYErrorResponseRouter is a struct that has a method to route the error response to the appropriate handler
func (service *WorkerService) RyErrorResponseRouter() func(server messagebus.Server, message proto.Message) (err error) {
	return func(server messagebus.Server, message proto.Message) (err error) {
		msg := message.(*tcwire.ErrorResponse)
		if msg.GetCode() == tcwire.ErrorResponse_TIMEOUT {
			return service.RyTimeoutHandler(server, message)
		} else {
			return defaulthandlers.ErrorResponseHandler(service.db)(server, message)
		}
	}
}
