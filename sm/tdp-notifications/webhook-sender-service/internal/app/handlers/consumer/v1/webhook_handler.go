package v1

import (
	"fmt"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/pkg/headers"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"google.golang.org/protobuf/proto"
)

func (h *handler) ProcessWebhookHandler(s messagebus.Server, msg proto.Message) error {
	if msg == nil {
		return fmt.Errorf("received nil msg")
	}

	request, _ := msg.(*datamanager.Notification)
	if request == nil {
		return fmt.Errorf("received invalid webhook notification message")
	}
	headers, err := headers.ParseHeaders(s)
	if err != nil {
		h.logger.Error("failed to extract headers", logger.Fields{"error": err})
		return err
	}
	err = h.s.ProcessWebhook(s.Context(), request, headers.XRetry)
	if err != nil {
		h.logger.Error("failed to process webhook", logger.Fields{"error": err})
		return err
	}

	h.logger.Info("webhook processed successfully")
	return nil
}
