package v1

import (
	"context"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"github.com/tucowsinc/tdp-shared-go/logger"
)

//go:generate mockery --name iService --output ../../../mocks --outpkg mocks --structname Service
type iService interface {
	SendEmail(ctx context.Context, notification *datamanager.Notification, msgHeaders map[string]any) error
}

type handler struct {
	s      iService
	logger logger.ILogger
}

func NewHandler(s iService, log logger.ILogger) *handler {
	return &handler{
		s:      s,
		logger: log,
	}
}

// RegisterHandlers  message handlers for message bus
func (h *handler) RegisterHandlers(bus messagebus.MessageBus) {
	bus.Register(&datamanager.Notification{}, h.EmailSenderHandler)
}
