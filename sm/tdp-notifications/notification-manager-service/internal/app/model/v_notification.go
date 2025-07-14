package model

import (
	"encoding/json"
	"errors"
	"time"

	"github.com/samber/lo"
	"github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"
	"google.golang.org/protobuf/types/known/timestamppb"
)

const DefaultUnProcessedEventBatchSize = 100

var protoStatusFromString = map[string]datamanager.DeliveryStatus{
	"received":   datamanager.DeliveryStatus_RECEIVED,
	"publishing": datamanager.DeliveryStatus_PUBLISHING,
	"published":  datamanager.DeliveryStatus_PUBLISHED,
	"failed":     datamanager.DeliveryStatus_FAILED,
}
var notificationStatusFromProto = lo.Invert(protoStatusFromString)

func VNotificationFromProto(req *datamanager.Notification) (*VNotification, error) {
	if req == nil {
		return nil, errors.New("notification is nil")
	}

	var createdAt *time.Time
	if req.GetCreatedDate() != nil {
		t := req.GetCreatedDate().AsTime()
		createdAt = &t
	}

	status := notificationStatusFromProto[req.GetStatus()]
	payload, err := extractPayloadJSON(req.GetData())
	if err != nil {
		return nil, err
	}
	var emailSubject, emailTemplate *string

	if email := req.GetEmailNotification(); email != nil {
		if envelope := email.GetEnvelope(); envelope != nil {
			emailSubject = lo.ToPtr(envelope.Subject)
		}
	}

	// Check and safely dereference optional fields
	tenantCustomerID := ""
	if req.TenantCustomerId != nil {
		tenantCustomerID = *req.TenantCustomerId
	}

	webhookURL := ""
	if req.WebhookUrl != nil {
		webhookURL = *req.WebhookUrl
	}

	signingSecret := ""
	if req.SigningSecret != nil {
		signingSecret = *req.SigningSecret
	}

	if createdAt == nil {
		return nil, errors.New("created date is nil")
	}

	return &VNotification{
		ID:               req.Id,
		NotificationID:   req.Id,
		Type:             req.Type,
		TenantID:         req.TenantId,
		TenantCustomerID: tenantCustomerID,
		WebhookURL:       webhookURL,
		SigningSecret:    signingSecret,
		CreatedDate:      *createdAt,
		Status:           status,
		StatusReason:     req.StatusReason,
		Payload:          *payload,
		EmailSubject:     lo.FromPtr(emailSubject),
		EmailTemplate:    lo.FromPtr(emailTemplate),
	}, nil
}

func extractPayloadJSON(anyData *anypb.Any) (*string, error) {
	if anyData == nil {
		return lo.ToPtr(""), nil
	}

	structData := &structpb.Struct{}
	if err := anyData.UnmarshalTo(structData); err != nil {
		return nil, err
	}

	// Convert struct to map
	mapData := structData.AsMap()

	// Marshal map to JSON string
	bytes, err := json.Marshal(mapData)
	if err != nil {
		return nil, err
	}

	str := string(bytes)
	return &str, nil
}

func VNotificationToProto(vn *VNotification) (*datamanager.Notification, error) {
	if vn == nil {
		return nil, errors.New("notification is nil")
	}

	protoStatus := protoStatusFromString[vn.Status]
	var createdDate *timestamppb.Timestamp

	createdDate = timestamppb.New(vn.CreatedDate)

	notification := &datamanager.Notification{
		Id:               vn.ID,
		Type:             vn.Type,
		TenantId:         vn.TenantID,
		TenantCustomerId: &vn.TenantCustomerID,
		WebhookUrl:       &vn.WebhookURL,
		SigningSecret:    &vn.SigningSecret,
		CreatedDate:      createdDate,
		Status:           protoStatus,
		StatusReason:     vn.StatusReason,
	}

	if vn.EmailSubject != "" || vn.EmailTemplate != "" {
		notification.NotificationDetails = &datamanager.Notification_EmailNotification{
			EmailNotification: &datamanager.EmailNotification{
				Envelope: &common.EmailEnvelope{
					Subject: vn.EmailSubject,
				},
			},
		}
	}

	if vn.Payload != "" {
		anyMsg, err := handlePayload(vn.Payload)
		if err != nil {
			return nil, err
		}
		notification.Data = anyMsg
	}

	return notification, nil
}

func handlePayload(payload string) (*anypb.Any, error) {

	var generic map[string]interface{}
	if err := json.Unmarshal([]byte(payload), &generic); err != nil {
		return nil, err
	}

	structData, err := structpb.NewStruct(generic)
	if err != nil {
		return nil, err
	}

	return anypb.New(structData)
}
