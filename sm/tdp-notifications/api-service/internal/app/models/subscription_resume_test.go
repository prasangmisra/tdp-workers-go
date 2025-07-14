package models

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestSubscriptionResumeRespFromProto(t *testing.T) {
	now := time.Now().UTC()
	// Helper function to convert metadata map to proto safely
	metadataToProtoSafe := func(t *testing.T, metadata map[string]interface{}) map[string]*anypb.Any {
		protoMetadata, err := MetadataToProto(metadata)
		require.NoError(t, err)
		return protoMetadata
	}

	metadata := map[string]interface{}{"key1": "value1"}
	metadataProto := metadataToProtoSafe(t, metadata)
	protoResponse := &subscription.SubscriptionResumeResponse{
		Subscription: &subscription.SubscriptionDetailsResponse{
			Id:                uuid.New().String(),
			NotificationEmail: "test@example.com",
			Url:               "https://webhook.com",
			Status:            subscription.SubscriptionStatus_ACTIVE,
			Tags:              []string{"tag1", "tag2"},
			Metadata:          metadataProto,
			NotificationTypes: []string{"DOMAIN_CREATED"},
			CreatedDate:       timestamppb.New(now),
			UpdatedDate:       timestamppb.New(now),
		},
	}

	// Call the function being tested
	resp := SubscriptionResumeRespFromProto(protoResponse)

	// Expected Result
	expected := &SubscriptionResumeResponse{
		Subscription: &Subscription{
			ID:                protoResponse.GetSubscription().GetId(),
			NotificationEmail: protoResponse.GetSubscription().GetNotificationEmail(),
			URL:               protoResponse.GetSubscription().GetUrl(),
			Status:            Active,
			Description:       nil,
			Tags:              protoResponse.GetSubscription().GetTags(),
			Metadata:          metadata,
			NotificationTypes: []string{"DOMAIN_CREATED"},
			CreatedDate:       &now,
			UpdatedDate:       &now,
		},
	}

	assert.Equal(t, expected, resp)
}
