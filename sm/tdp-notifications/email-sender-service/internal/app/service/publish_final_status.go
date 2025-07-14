package service

import (
	"context"
	"fmt"

	proto "github.com/tucowsinc/tdp-messages-go/message/datamanager"
)

const (
	emptyNotificationReason      = "email notification is empty"
	nilNotificationReason        = "notification is nil"
	errorDecodingDataReason      = "error decoding template variables data"
	errorRenderingTemplateReason = "error rendering template"
	errorSendingEmailReason      = "error sending email"
	successReason                = "SUCCESS"
)

func (s *service) publishFinalStatus(ctx context.Context, status proto.DeliveryStatus, reason string, notification *proto.Notification, headers map[string]any) error {
	notification.Status = status
	notification.StatusReason = reason
	_, err := s.bus.Send(ctx, s.statusQ, notification, headers)
	if err != nil {
		return fmt.Errorf("failed to send message to queue %s: %w", s.statusQ, err)
	}
	return nil
}
