package models

import (
	"github.com/stretchr/testify/require"
	proto "github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"
	"google.golang.org/protobuf/types/known/timestamppb"
	"testing"
	"time"
)

func TestRequestFromProto(t *testing.T) {
	t.Parallel()

	anypbFromMap := func(m map[string]any) *anypb.Any {
		structData, err := structpb.NewStruct(m)
		require.NoError(t, err, "Failed to create *structpb.Struct")
		anyData, err := anypb.New(structData)
		require.NoError(t, err, "Failed to create *anypb.Any")
		return anyData
	}

	now := time.Now().UTC()
	tests := []struct {
		name       string
		reqProto   *proto.Notification
		expected   *Request
		requireErr require.ErrorAssertionFunc
	}{
		{
			name:       "nil request",
			requireErr: require.NoError,
		},
		{
			name:       "empty request",
			reqProto:   &proto.Notification{},
			expected:   &Request{},
			requireErr: require.NoError,
		},
		{
			name:       "invalid Data in request",
			reqProto:   &proto.Notification{Data: &anypb.Any{}},
			requireErr: require.Error,
		},
		{
			name:       "valid request - all fields set",
			requireErr: require.NoError,
			reqProto: &proto.Notification{
				Id:             "notification_id",
				Type:           "notification_type",
				SubscriptionId: "sub_12345",
				CreatedDate:    timestamppb.New(now),
				Data:           anypbFromMap(map[string]any{"key": "value"}),
			},
			expected: &Request{
				NotificationID:   "notification_id",
				NotificationType: "notification_type",
				SubscriptionID:   "sub_12345",
				CreatedDate:      now.Format(time.RFC3339),
				Payload:          map[string]any{"key": "value"},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			actual, err := RequestFromProto(tt.reqProto)
			tt.requireErr(t, err)
			require.Equal(t, tt.expected, actual)
		})
	}
}
