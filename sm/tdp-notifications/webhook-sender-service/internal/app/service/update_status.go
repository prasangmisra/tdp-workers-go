package service

import (
	"context"
	"fmt"

	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"github.com/tucowsinc/tdp-shared-go/logger"
)

func (s *Service) PublishToFinalStatusQueue(ctx context.Context, req *datamanager.Notification, log logger.ILogger) error {
	if s.Bus == nil {
		return fmt.Errorf("message bus not initialized to publish to final status queue")
	}
	log.Info("Publishing final status of notification", logger.Fields{
		"queue":  s.FinalStatusQueue,
		"status": req.Status,
	})

	_, err := s.Bus.Send(ctx, s.FinalStatusQueue, req, nil)
	if err != nil {
		return fmt.Errorf("failed to send message to queue %s: %w", s.FinalStatusQueue, err)
	}

	return nil
}
