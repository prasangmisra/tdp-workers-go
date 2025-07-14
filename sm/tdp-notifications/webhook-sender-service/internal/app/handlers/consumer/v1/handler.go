package v1

import (
	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/app/service"
	"github.com/tucowsinc/tdp-shared-go/logger"
)

type handler struct {
	s      service.IService
	logger logger.ILogger
}

func NewHandler(s service.IService, log logger.ILogger) *handler {
	return &handler{
		s:      s,
		logger: log,
	}
}

// RegisterHandlers  message handlers for message bus
func (h *handler) RegisterHandlers() {
	h.s.MessageBus().Register(&datamanager.Notification{}, h.ProcessWebhookHandler)
}
