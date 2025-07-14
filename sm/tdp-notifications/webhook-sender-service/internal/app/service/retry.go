package service

import (
	"context"
	"fmt"

	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/pkg/headers"
	"github.com/tucowsinc/tdp-shared-go/logger"
)

// GetNextRetryQueue returns the next retry queue based on the current retry count.
func (s *Service) GetNextRetryQueue(retryCount int) (string, error) {
	if retryCount >= len(s.Cfg.RMQ.RetryQueues) {
		return "", fmt.Errorf("no more retry queues available")
	}
	return s.Cfg.RMQ.RetryQueues[retryCount].Name, nil
}

func (s *Service) PublishToRetryQueue(ctx context.Context, queueName string, req *datamanager.Notification, retryCount int, log logger.ILogger) error {
	if s.Bus == nil {
		return fmt.Errorf("message bus not initialized to publish to retry queue")
	}
	newRetryCount := retryCount + 1
	log.Info("Publishing message to queue", logger.Fields{
		"queue":               queueName,
		"retry_count":         retryCount,
		headers.X_RETRY:       fmt.Sprintf("%d", newRetryCount),
		headers.EXPIRES_IN_MS: s.Cfg.RMQ.RetryQueues[retryCount].TTL * 1000,
	})
	requestHeaders := map[string]any{
		headers.X_RETRY:       fmt.Sprintf("%d", newRetryCount),
		headers.EXPIRES_IN_MS: s.Cfg.RMQ.RetryQueues[retryCount].TTL * 1000,
	}

	_, err := s.Bus.Send(ctx, queueName, req, requestHeaders)
	if err != nil {
		log.Error("Message publishing to queue failed", logger.Fields{
			"queue": queueName,
			"error": err.Error(),
		})
		return fmt.Errorf("failed to send message to queue %s: %w", queueName, err)
	}

	log.Info("Message published to retry queue", logger.Fields{
		"queue":       queueName,
		"retry_count": retryCount,
	})

	return nil
}
