package service

import (
	"context"
	"fmt"

	proto "github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"github.com/tucowsinc/tdp-notifications/email-sender-service/internal/app/model/esender"
	"github.com/tucowsinc/tdp-notifications/email-sender-service/internal/app/service/template"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"

	"github.com/tucowsinc/tdp-shared-go/logger"
)

func (s *service) SendEmail(ctx context.Context, notification *proto.Notification, msgHeaders map[string]any) error {
	log := s.logger.CreateChildLogger(logger.Fields{"notification_id": notification.GetId()})

	if notification == nil {
		log.Warn("email notification delivery failed", logger.Fields{"reason": nilNotificationReason})
		return s.publishFinalStatus(ctx, proto.DeliveryStatus_FAILED, nilNotificationReason, notification, msgHeaders)
	}
	emailNotification := notification.GetEmailNotification()

	if emailNotification == nil {
		log.Warn("email notification delivery failed", logger.Fields{"reason": emptyNotificationReason})
		return s.publishFinalStatus(ctx, proto.DeliveryStatus_FAILED, emptyNotificationReason, notification, msgHeaders)
	}

	// Get the envelope from the notification
	envelope := emailNotification.GetEnvelope()

	// Get the template variables from the notification data
	templateVariables, err := decodeAnyToMap(notification.Data)
	if err != nil {
		log.Error(errorDecodingDataReason, logger.Fields{"error": err})
		reason := fmt.Sprintf("%s: %s", errorDecodingDataReason, err.Error())
		return s.publishFinalStatus(ctx, proto.DeliveryStatus_FAILED, reason, notification, msgHeaders)
	}

	// Render the email body using the template and variables
	body, err := template.RenderTemplate(emailNotification.GetTemplate(), templateVariables)
	if err != nil {
		log.Error(errorRenderingTemplateReason, logger.Fields{"error": err})
		reason := fmt.Sprintf("%s: %s", errorRenderingTemplateReason, err.Error())
		return s.publishFinalStatus(ctx, proto.DeliveryStatus_FAILED, reason, notification, msgHeaders)
	}

	msg := esender.MessageFromProto(envelope.GetSubject(), body)
	from := esender.AddressFromProto(envelope.GetFromAddress())
	replyTo := esender.AddressFromProto(envelope.GetReplytoAddress())
	to := esender.AddressesFromProto(envelope.GetToAddress())
	cc := esender.AddressesFromProto(envelope.GetCcAddress())
	bcc := esender.AddressesFromProto(envelope.GetBccAddress())

	err = s.emailSender.SendEmail(ctx, msg, from, replyTo, to, cc, bcc)
	if err != nil {
		err = fmt.Errorf("%s: %w", errorSendingEmailReason, err)
		log.Warn("email notification delivery failed", logger.Fields{"error": err})
		return s.publishFinalStatus(ctx, proto.DeliveryStatus_FAILED, err.Error(), notification, msgHeaders)
	}
	return s.publishFinalStatus(ctx, proto.DeliveryStatus_PUBLISHED, successReason, notification, msgHeaders)
}

// Helper method: decodeAnyToMap safely unmarshals an Any proto into map[string]interface{}
func decodeAnyToMap(data *anypb.Any) (map[string]interface{}, error) {
	if data == nil {
		return map[string]interface{}{}, nil
	}

	structData := &structpb.Struct{}
	if err := data.UnmarshalTo(structData); err != nil {
		return nil, fmt.Errorf("failed to unmarshal Any to Struct: %w", err)
	}

	return structData.AsMap(), nil
}
