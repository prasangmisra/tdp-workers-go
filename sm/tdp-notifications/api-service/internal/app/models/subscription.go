package models

import (
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/converters"

	"time"

	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type Subscription struct {
	ID                string                 `json:"id"`
	NotificationEmail string                 `json:"notification_email"`
	URL               string                 `json:"url"`
	Description       *string                `json:"description"`
	Tags              []string               `json:"tags"`
	Metadata          map[string]interface{} `json:"metadata,omitempty"`
	Status            SubscriptionStatus     `json:"status"`
	NotificationTypes []string               `json:"notification_types"`
	CreatedDate       *time.Time             `json:"created_date"`
	UpdatedDate       *time.Time             `json:"updated_date"`
} // @name Subscription

func subscriptionFromProtoHelper(m *subscription.SubscriptionDetailsResponse) *Subscription {
	return converters.ConvertOrNil(m, func(m *subscription.SubscriptionDetailsResponse) Subscription {
		return Subscription{
			ID:                m.GetId(),
			NotificationEmail: m.GetNotificationEmail(),
			URL:               m.GetUrl(),
			Description:       converters.StringToPtr(m.GetDescription()),
			Tags:              m.GetTags(),
			Metadata:          MetadataFromProto(m.GetMetadata()),
			Status:            subscriptionStatusFromProto[m.GetStatus()],
			NotificationTypes: m.GetNotificationTypes(),
			CreatedDate:       converters.ConvertOrNil(m.GetCreatedDate(), func(t *timestamppb.Timestamp) time.Time { return t.AsTime() }),
			UpdatedDate:       converters.ConvertOrNil(m.GetUpdatedDate(), func(t *timestamppb.Timestamp) time.Time { return t.AsTime() }),
		}
	})
}

// MetadataFromProto converts a map[string]*anypb.Any to a map[string]interface{}
func MetadataFromProto(anyMap map[string]*anypb.Any) map[string]interface{} {
	if anyMap == nil {
		return nil
	}

	result := make(map[string]interface{})

	for key, anyValue := range anyMap {
		var structValue structpb.Value
		if err := anyValue.UnmarshalTo(&structValue); err == nil {
			result[key] = structValue.AsInterface()
		} else {
			result[key] = anyValue
		}
	}
	return result
}

// MetadataToProto converts the metadata from the Model format to the protobuf message format
func MetadataToProto(metadata map[string]interface{}) (map[string]*anypb.Any, error) {
	if metadata == nil {
		return nil, nil
	}
	convertedMetadata := make(map[string]*anypb.Any)
	for key, value := range metadata {
		var structValue *structpb.Value
		if value == nil {
			// Explicitly set to null
			structValue = structpb.NewNullValue()
		} else {
			var err error
			structValue, err = structpb.NewValue(value)
			if err != nil {
				return nil, err
			}
		}
		anyValue, err := anypb.New(structValue)
		if err != nil {
			return nil, err
		}

		convertedMetadata[key] = anyValue

	}
	return convertedMetadata, nil
}
