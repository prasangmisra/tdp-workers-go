package v1

import (
	"context"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"github.com/tucowsinc/tdp-notifications/notification-manager-service/internal/app/config"
	"github.com/tucowsinc/tdp-shared-go/logger"
)

//go:generate mockery --name IService --output ../../../mock/rest/handlers --outpkg handlersmock
type IService interface {
	UpdateNotificationStatus(context.Context, *datamanager.Notification) error
}

type handler struct {
	s      IService
	logger logger.ILogger
	cfg    config.Config
	bus    messagebus.MessageBus
}

func NewHandler(s IService, log logger.ILogger, cfg config.Config, bus messagebus.MessageBus) *handler {
	return &handler{
		s:      s,
		logger: log,
		cfg:    cfg,
		bus:    bus,
	}
}

// Register  message handlers for message bus
func (h *handler) Register() {
	h.bus.Register(&datamanager.Notification{}, h.UpdateNotificationStatusHandler)
}
