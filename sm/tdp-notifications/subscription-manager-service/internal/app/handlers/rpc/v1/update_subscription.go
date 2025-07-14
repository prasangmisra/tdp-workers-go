package v1

import (
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message"
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	logging "github.com/tucowsinc/tdp-shared-go/logger"
	"google.golang.org/protobuf/proto"
)

func (h *handler) UpdateSubscriptionHandler(s messagebus.Server, msg proto.Message) error {
	request, _ := msg.(*subscription.SubscriptionUpdateRequest)
	if request == nil {
		return s.ErrorReply(message.ErrorResponse_BAD_REQUEST, "empty request or wrong request message type", "", false, msg)
	}

	resp, err := h.s.UpdateSubscription(s.Context(), request)
	if err != nil {
		h.logger.Error("error updating subscription", logging.Fields{"error": err})
		return err
	}

	if err = s.Reply(resp, nil); err != nil {
		h.logger.Error("error replying to the caller", logging.Fields{"error": err})
	}

	return err
}
