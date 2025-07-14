package models

import (
	"fmt"
	proto "github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"google.golang.org/protobuf/types/known/structpb"
	"time"
)

type Request struct {
	NotificationID   string         `json:"id,omitempty"`
	NotificationType string         `json:"notification_typ,omitempty"`
	SubscriptionID   string         `json:"subscription_id,omitempty"`
	CreatedDate      string         `json:"created_date,omitempty"`
	Payload          map[string]any `json:"payload,omitempty"`
}

func RequestFromProto(reqProto *proto.Notification) (*Request, error) {
	if reqProto == nil {
		return nil, nil
	}

	req := &Request{
		NotificationID:   reqProto.GetId(),
		NotificationType: reqProto.GetType(),
		SubscriptionID:   reqProto.GetSubscriptionId(),
	}

	if createdDate := reqProto.GetCreatedDate(); createdDate != nil {
		req.CreatedDate = createdDate.AsTime().Format(time.RFC3339)
	}

	if reqProto.GetData() == nil {
		return req, nil
	}

	// Decode Data into a structpb.Struct (Protobuf equivalent of JSON)
	var structData structpb.Struct
	if err := reqProto.GetData().UnmarshalTo(&structData); err != nil {
		return nil, fmt.Errorf("failed to unmarshal protobuf Any to Struct: %w", err)
	}

	req.Payload = structData.AsMap()
	return req, nil
}
