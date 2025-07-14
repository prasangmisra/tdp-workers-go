package v1

import (
	"errors"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"google.golang.org/protobuf/proto"
)

func (h *handler) EmailSenderHandler(mbs messagebus.Server, msg proto.Message) error {
	notification, _ := msg.(*datamanager.Notification)
	if notification == nil {
		h.logger.Error("received an empty notification")
		return errors.New("invalid proto message")
	}

	return h.s.SendEmail(mbs.Context(), notification, mbs.Headers())

}
