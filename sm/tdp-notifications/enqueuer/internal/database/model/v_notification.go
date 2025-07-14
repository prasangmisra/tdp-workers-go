package model

import (
	"encoding/json"
	"fmt"

	"github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"github.com/tucowsinc/tdp-notifications/enqueuer/internal/types"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// TODO - this should be combined with the v_notification.go source in the notification manager service module,
// and placed into a single shared source file under /pkg

const DefaultUnProcessedEventBatchSize = 100

var notificationStatusToProto = map[string]datamanager.DeliveryStatus{
	"received":    datamanager.DeliveryStatus_RECEIVED,
	"publishing":  datamanager.DeliveryStatus_PUBLISHING,
	"published":   datamanager.DeliveryStatus_PUBLISHED,
	"failed":      datamanager.DeliveryStatus_FAILED,
	"unsupported": datamanager.DeliveryStatus_UNSUPPORTED,
}

// Helper function to convert the gorm generated VNotification to a proto message
func (s *VNotification) ToWebhookProto() (proto.Message, error) {

	// Need to convert the s.Payload (which is a string of JSON) into a *anypb.Any so we can put it on the proto message
	// First, unmarshal the json payload into a map
	var result map[string]interface{}
	err := json.Unmarshal([]byte(*s.Payload), &result)
	if err != nil {
		return nil, err
	}

	// Convert map to structpb.Value
	structValue, err := structpb.NewStruct(result)
	if err != nil {
		return nil, err
	}

	// Convert structpb.Value to anypb.Any
	anyData, err := anypb.New(structValue)
	if err != nil {
		fmt.Println("Error using New:", err.Error())
	}

	msg := &datamanager.Notification{
		Id:               *s.ID,
		Type:             *s.Type,
		TenantId:         *s.TenantID,
		TenantCustomerId: s.TenantCustomerID,
		WebhookUrl:       s.WebhookURL,
		SigningSecret:    s.SigningSecret,
		CreatedDate:      timestamppb.New(*s.CreatedDate),
		Status:           notificationStatusToProto[*s.Status],
		Data:             anyData,
	}
	return msg, nil
}

func (n *VNotification) ToEmailProto() (proto.Message, error) {
	// Convert the gorm generated VNotification to a proto Notification message for email

	// First, some basic error checks:
	if n == nil {
		return nil, fmt.Errorf("VNotification is nil")
	}
	if n.ChannelType == nil {
		return nil, fmt.Errorf("channel type is nil for notification %s", types.PointerToValue(n.NotificationID))
	}

	if n.EmailTemplate == nil {
		return nil, fmt.Errorf("email template is nil for notification %s", types.PointerToValue(n.NotificationID))
	}

	if n.Payload == nil {
		return nil, fmt.Errorf("payload is nil for notification %s", types.PointerToValue(n.NotificationID))
	}

	// The expectation here is that s.Payload is a JSON string that is composed of two parts:
	// 1. Data: a map of key/value pairs that are used to render the template
	// 2. Envelope: A message envelope (e.g. destination email address, subject, etc.)

	// We need to extract these two elements from s.Payload and set them as appropriate fields on the proto message

	// First, unmarshal the json payload into a map
	var payloadJson map[string]interface{}
	err := json.Unmarshal([]byte(*n.Payload), &payloadJson)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal payload for notification %s: %w", types.PointerToValue(n.NotificationID), err)
	}

	// PART 1: DATA
	// Extract the "data" from payload - this is a map of the variables/values that will be passed to the template for rendering
	dataJson := payloadJson["data"]
	if dataJson == nil {
		return nil, fmt.Errorf("data is nil for notification %s", types.PointerToValue(n.NotificationID))
	}

	// Make sure that dataJson is a map
	dataJsonMap, ok := dataJson.(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("data is not a map for notification %s", types.PointerToValue(n.NotificationID))
	}

	// Convert map to structpb.Value
	structValue, err := structpb.NewStruct(dataJsonMap)
	if err != nil {
		return nil, fmt.Errorf("failed to convert dataJson to structpb for notification %s: %w", types.PointerToValue(n.NotificationID), err)
	}
	// Convert structpb.Value to anypb.Any
	anyData, err := anypb.New(structValue)
	if err != nil {
		return nil, fmt.Errorf("failed to convert structValue to 'any' for notification %s: %w", types.PointerToValue(n.NotificationID), err)
	}

	// PART 2: ENVELOPE
	// Extract the envelope information
	envelopeJson := payloadJson["envelope"]
	if envelopeJson == nil {
		return nil, fmt.Errorf("envelope is nil for notification %s", types.PointerToValue(n.NotificationID))
	}

	// Convert the envelope JSON to a byte array
	envelopeJsonBytes, err := json.Marshal(envelopeJson)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal envelopeJson for notification %s: %w", types.PointerToValue(n.ID), err)
	}
	envelope := &common.EmailEnvelope{}
	// Use the protojson package to unmarshal the JSON into the EmailEnvelope struct
	protojson.Unmarshal(envelopeJsonBytes, envelope)

	// Create the EmailNotification object
	// - Use the envelope we just unmarshalled
	// - Get the template from the VNotification struct
	emailNotification := &datamanager.EmailNotification{
		Envelope: envelope,
		Template: types.PointerToValue(n.EmailTemplate),
	}

	// Check if any of the remaining required fields are nill
	if n.ID == nil {
		return nil, fmt.Errorf("ID is nil for notification %s", types.PointerToValue(n.NotificationID))
	}
	if n.Type == nil {
		return nil, fmt.Errorf("type is nil for notification %s", types.PointerToValue(n.NotificationID))
	}
	if n.TenantID == nil {
		return nil, fmt.Errorf("tenant ID is nil for notification %s", types.PointerToValue(n.NotificationID))
	}
	if n.CreatedDate == nil {
		return nil, fmt.Errorf("created date is nil for notification %s", types.PointerToValue(n.NotificationID))
	}

	msg := &datamanager.Notification{
		Id:                  *n.ID,
		Type:                *n.Type,
		TenantId:            *n.TenantID,
		TenantCustomerId:    n.TenantCustomerID,
		NotificationDetails: &datamanager.Notification_EmailNotification{EmailNotification: emailNotification},
		CreatedDate:         timestamppb.New(*n.CreatedDate),
		Status:              notificationStatusToProto[*n.Status],
		Data:                anyData,
	}
	return msg, nil
}
