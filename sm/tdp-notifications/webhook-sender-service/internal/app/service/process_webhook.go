package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/app/models"

	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	encryption "github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/pkg/encryption"
	"github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/pkg/rest"
	"github.com/tucowsinc/tdp-shared-go/logger"
)

// ProcessWebhook processes the incoming webhook request
func (s *Service) ProcessWebhook(ctx context.Context, req *datamanager.Notification, retryCount int) error {
	if req == nil {
		return fmt.Errorf("received nil request")
	}

	log := s.Logger.CreateChildLogger(logger.Fields{
		"notification_id": req.Id,
	})

	if maxRetryCount := len(s.Cfg.RMQ.RetryQueues); retryCount > maxRetryCount { // exceeded max retry count
		log.Info("Retry attempts exceeded maximum value, moving to final status queue",
			logger.Fields{"retry_count": retryCount, "max_retry_count": maxRetryCount})
		req.Status = datamanager.DeliveryStatus_FAILED
		return s.PublishToFinalStatusQueue(ctx, req, log)
	}

	payload, err := s.validateRequest(req)
	if err != nil {
		log.Error("Invalid request, moving to final status queue", logger.Fields{"error": err})
		req.Status = datamanager.DeliveryStatus_FAILED
		return s.PublishToFinalStatusQueue(ctx, req, log)
	}

	secret := *req.SigningSecret
	signedPayload := encryption.SignPayload(payload, secret)

	var shouldRetry, isNetworkError bool

	// Send POST request
	statusCode, err := s.HTTPClient.SendPostRequest(ctx, *req.WebhookUrl, payload, signedPayload, req.Id, log)
	if err != nil {
		isNetworkError = errors.Is(err, rest.ErrNetwork)
		log.Error("Webhook request failed", logger.Fields{
			"error":          err,
			"status_code":    statusCode, // Might be 0 if error occurred before response
			"isNetworkError": isNetworkError,
		})

		shouldRetry = isNetworkError
		if !isNetworkError {
			req.Status = datamanager.DeliveryStatus_FAILED
			req.StatusReason = "Network error"
			return s.PublishToFinalStatusQueue(ctx, req, log)
		}
	} else {
		switch {
		case statusCode >= 500:
			log.Error("Webhook request failed due to server error", logger.Fields{
				"status_code": statusCode,
			})
			//retry all server errors
			shouldRetry = true

		case statusCode >= 400:
			log.Error("Webhook request failed due to 4xx error", logger.Fields{
				"status_code": statusCode,
			})
			req.Status = datamanager.DeliveryStatus_FAILED
			req.StatusReason = "4xx Client error"
			return s.PublishToFinalStatusQueue(ctx, req, log)

		case statusCode >= 300:
			log.Error("Webhook request failed due to redirection error", logger.Fields{
				"status_code": statusCode,
			})
			req.Status = datamanager.DeliveryStatus_FAILED
			req.StatusReason = "Redirections not supported for webhook URLs"
			return s.PublishToFinalStatusQueue(ctx, req, log)

		default:
			// request is successful, no need to retry
			shouldRetry = false
		}
	}
	if shouldRetry {
		if retryCount >= len(s.Cfg.RMQ.RetryQueues) {
			log.Error("Maximum number of retries exceeded", logger.Fields{
				"error":       err,
				"status_code": statusCode,                 // Might be 0 if error occurred before response
				"max_retries": len(s.Cfg.RMQ.RetryQueues), //might be a function on RMQ configs
			})
			req.Status = datamanager.DeliveryStatus_FAILED
			// No need to set status reason, as it is already set from the previous error
			return s.PublishToFinalStatusQueue(ctx, req, log)
		}
		return s.PublishToRetryQueue(ctx, s.Cfg.RMQ.RetryQueues[retryCount].Name, req, retryCount, log)
	}

	// Mark request as published and move to final status queue
	req.Status = datamanager.DeliveryStatus_PUBLISHED
	req.StatusReason = "SUCCESS"
	return s.PublishToFinalStatusQueue(ctx, req, log)
}

// validateRequest does some sanity checks on the request params
// It checks if the retryCount is fine, if webhook_url is present, the payload is extracted
// and the signing_secret is present.
// If any of these conditions are not met, we cannot proceed with the
func (s *Service) validateRequest(req *datamanager.Notification) ([]byte, error) {
	if req.WebhookUrl == nil {
		return nil, fmt.Errorf("webhook_url is nil")
	}

	if req.SigningSecret == nil {
		return nil, fmt.Errorf("signing_secret is nil")
	}

	webhookReq, err := models.RequestFromProto(req)
	if err != nil {
		return nil, fmt.Errorf("failed to convert proto message to webhook request: %w", err)
	}

	reqBytes, err := json.Marshal(webhookReq)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal webhook request: %w", err)
	}

	return reqBytes, nil
}
