package v1

import (
	"errors"

	_ "github.com/lpar/problem"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message"
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	smerrors "github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/errors"
	_ "github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/model"
	logging "github.com/tucowsinc/tdp-shared-go/logger"
	"google.golang.org/protobuf/proto"
)

func (h *handler) DeleteSubscriptionByIDHandler(s messagebus.Server, msg proto.Message) error {
	request, _ := msg.(*subscription.SubscriptionDeleteRequest)
	if request == nil {
		return s.ErrorReply(message.ErrorResponse_BAD_REQUEST, "empty request or wrong request message type", "", false, msg)
	}
	resp, err := h.s.DeleteSubscriptionByID(s.Context(), request)
	if errors.Is(err, smerrors.ErrNotFound) {
		return s.ErrorReply(message.ErrorResponse_NOT_FOUND, "subscription not found", "", false, msg)
	}
	if err != nil {
		h.logger.Error("error deleting subscription", logging.Fields{"error": err})
		return err
	}
	if err = s.Reply(resp, nil); err != nil {
		h.logger.Error("error replying to the caller", logging.Fields{"error": err})
	}
	return err
}
