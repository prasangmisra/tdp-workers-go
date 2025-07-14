package service

import (
	"context"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/app/config"
	"github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/pkg/rest"
	"github.com/tucowsinc/tdp-shared-go/logger"
)

//go:generate mockery --name IService --output ../mock --outpkg mock
type IService interface {
	ProcessWebhook(ctx context.Context, req *datamanager.Notification, retryCount int) error
	MessageBus() messagebus.MessageBus
}

type Service struct {
	Cfg                   *config.Config
	Bus                   messagebus.MessageBus
	NotificationPullQueue string
	FinalStatusQueue      string
	Logger                logger.ILogger
	HTTPClient            rest.IHTTPClient
}

// New initializes a new Service instance.
// It reads the retry queues from config and sorts them by TTL.
func New(cfg *config.Config, log logger.ILogger, bus messagebus.MessageBus, httpClient rest.IHTTPClient) *Service {
	// Copy the retry queues from config

	return &Service{
		Cfg:                   cfg,
		Bus:                   bus,
		NotificationPullQueue: cfg.RMQ.WebhookSendQueue.Name,
		FinalStatusQueue:      cfg.RMQ.FinalStatusQueue.Name,
		Logger:                log,
		HTTPClient:            httpClient,
	}
}

func (s *Service) MessageBus() messagebus.MessageBus {
	return s.Bus
}
