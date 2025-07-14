package v1

import (
	"errors"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	nmerrors "github.com/tucowsinc/tdp-notifications/notification-manager-service/internal/app/errors"

	"google.golang.org/protobuf/proto"
)

func (h *handler) UpdateNotificationStatusHandler(s messagebus.Server, msg proto.Message) error {
	// We have received a message that contains the "final" status of a notification (i.e. PUBLISHED, FAILED, etc)
	// Dispatch this to the service method
	// Even though we return an error - this message has no consumer.  So the returned error (if any) doesn't go anywhere

	err := h.s.UpdateNotificationStatus(s.Context(), msg.(*datamanager.Notification))
	// err should be handled by the WithErrorReply handler in handler.go
	if errors.Is(err, nmerrors.ErrInvalidFinalStatus) {
		h.logger.Warn("Notification's final status was processed, but was not 'published' or 'failed'; discarding message.")
		return nil
	}
	// If an error (that *isn't* a connectivity error) occured, we throw an error; this will cause a negative ack back to RMQ.
	// If we configure a DLQ for this queue, this non-acked message will be sent to that DLQ
	// We can then create some monitoring tools to monitor the DLQ and alert us if there are too many messages in the DLQ
	// For now, we don't need to worry about that.  Just return the error.
	return err
}
