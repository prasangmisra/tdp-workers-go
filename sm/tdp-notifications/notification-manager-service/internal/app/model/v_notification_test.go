package model

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/samber/lo"
	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestVNotificationToProto(t *testing.T) {
	t.Parallel()
	now := time.Now().UTC()
	emailSubject := "Test Subject"
	emailTemplate := "This is a template"
	notificationID := "notif-1"
	status := "published"
	tests := []struct {
		name       string
		input      *VNotification
		expected   *datamanager.Notification
		requireErr require.ErrorAssertionFunc
	}{
		{
			name:     "vn is nil",
			input:    nil,
			expected: nil,
			requireErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.Error(t, err)
				require.Contains(t, err.Error(), "notification is nil")
			},
		},
		{
			name: "created date is nil",
			input: &VNotification{
				ID:     notificationID,
				Status: status,
			},
			expected: &datamanager.Notification{
				Id:     notificationID,
				Status: datamanager.DeliveryStatus_PUBLISHED,
			},
			requireErr: require.NoError,
		},
		{
			name: "email subject and template present",
			input: &VNotification{
				ID:            notificationID,
				Status:        status,
				EmailSubject:  emailSubject,
				EmailTemplate: emailTemplate,
			},
			expected: &datamanager.Notification{
				Id:     notificationID,
				Status: datamanager.DeliveryStatus_PUBLISHED,
				NotificationDetails: &datamanager.Notification_EmailNotification{
					EmailNotification: &datamanager.EmailNotification{
						Envelope: &common.EmailEnvelope{
							Subject: emailSubject,
						},
					},
				},
			},
			requireErr: require.NoError,
		},
		{
			name: "payload unmarshalled correctly (plain JSON)",
			input: func() *VNotification {
				payload := `{
					"envelope": {"subject": "Test Subject"},
					"data": {"first_name": "Prasang"}
				}`
				return &VNotification{
					ID:      "notif-1",
					Status:  "published",
					Payload: payload,
				}
			}(),
			expected: func() *datamanager.Notification {
				structData, err := structpb.NewStruct(map[string]interface{}{
					"envelope": map[string]interface{}{
						"subject": "Test Subject",
					},
					"data": map[string]interface{}{
						"first_name": "Prasang",
					},
				})
				require.NoError(t, err)

				anyMsg, err := anypb.New(structData)
				require.NoError(t, err)

				return &datamanager.Notification{
					Id:     "notif-1",
					Status: datamanager.DeliveryStatus_PUBLISHED,
					Data:   anyMsg,
				}
			}(),
			requireErr: require.NoError,
		},
		{
			name: "all fields",
			input: &VNotification{
				ID:               "notif-4",
				Type:             "test-type",
				TenantID:         "tenant-123",
				TenantCustomerID: "cust-456",
				WebhookURL:       "https://example.com",
				SigningSecret:    "secret",
				Status:           "failed",
				StatusReason:     "auth error",
				CreatedDate:      now,
			},
			expected: &datamanager.Notification{
				Id:               "notif-4",
				Type:             "test-type",
				TenantId:         "tenant-123",
				TenantCustomerId: lo.ToPtr("cust-456"),
				WebhookUrl:       lo.ToPtr("https://example.com"),
				SigningSecret:    lo.ToPtr("secret"),
				Status:           datamanager.DeliveryStatus_FAILED,
				StatusReason:     "auth error",
				CreatedDate:      timestamppb.New(now),
			},
			requireErr: require.NoError,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			actual, err := VNotificationToProto(tc.input)
			tc.requireErr(t, err)
			if tc.expected == nil {
				require.Nil(t, actual)
				return
			}

			require.NotNil(t, actual)
			require.Equal(t, tc.expected.Id, actual.Id)
			require.Equal(t, tc.expected.Status, actual.Status)
			// Have to do this since anypb does not preserve the sequence of json
			if tc.expected.Data != nil && actual.Data != nil {
				expectedJSON, err := protojson.Marshal(tc.expected.Data)
				require.NoError(t, err)

				actualJSON, err := protojson.Marshal(actual.Data)
				require.NoError(t, err)

				require.JSONEq(t, string(expectedJSON), string(actualJSON))
			} else {
				require.Equal(t, tc.expected.Data, actual.Data)
			}
		})

	}
}

func TestVNotificationFromProto(t *testing.T) {
	t.Parallel()
	structData, err := structpb.NewStruct(map[string]interface{}{
		"data": map[string]interface{}{
			"name": "Prasang",
		},
	})
	require.NoError(t, err)
	anyData, err := anypb.New(structData)
	require.NoError(t, err)

	payloadStruct := map[string]interface{}{
		"data": map[string]interface{}{
			"name": "Prasang",
		},
	}
	payloadBytes, _ := json.Marshal(payloadStruct)
	payloadStr := string(payloadBytes)
	now := time.Now().UTC()
	tests := []struct {
		name       string
		input      *datamanager.Notification
		expected   *VNotification
		requireErr require.ErrorAssertionFunc
	}{
		{
			name:     "nil input",
			input:    nil,
			expected: nil,
			requireErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.Error(t, err)
				require.Contains(t, err.Error(), "notification is nil")
			},
		},
		{
			name: "created date is nil",
			input: &datamanager.Notification{
				Id:     "notif-3",
				Status: datamanager.DeliveryStatus_PUBLISHED,
				NotificationDetails: &datamanager.Notification_EmailNotification{
					EmailNotification: &datamanager.EmailNotification{
						Envelope: &common.EmailEnvelope{
							Subject: "Subject Line",
						},
					},
				},
				Data: anyData,
			},
			expected: nil,
			requireErr: func(t require.TestingT, err error, _ ...interface{}) {
				require.Error(t, err)
				require.Contains(t, err.Error(), "created date is nil")
			},
		},
		{
			name: "email fields populated",
			input: &datamanager.Notification{
				Id:     "notif-3",
				Status: datamanager.DeliveryStatus_PUBLISHED,
				NotificationDetails: &datamanager.Notification_EmailNotification{
					EmailNotification: &datamanager.EmailNotification{
						Envelope: &common.EmailEnvelope{
							Subject: "Subject Line",
						},
					},
				},
				Data:        anyData,
				CreatedDate: timestamppb.New(now),
			},
			expected: &VNotification{
				ID:             "notif-3",
				NotificationID: "notif-3",
				Status:         "published",
				EmailSubject:   "Subject Line",
				Payload:        payloadStr,
				CreatedDate:    now,
			},
			requireErr: require.NoError,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			actual, err := VNotificationFromProto(tc.input)

			tc.requireErr(t, err)
			if tc.expected == nil {
				require.Nil(t, actual)
				return
			}

			require.NotNil(t, actual)
			require.Equal(t, tc.expected.ID, actual.ID)
			require.Equal(t, tc.expected.Status, actual.Status)
			require.Equal(t, tc.expected.NotificationID, actual.NotificationID)
			require.Equal(t, tc.expected.EmailSubject, actual.EmailSubject)
			require.Equal(t, tc.expected.EmailTemplate, actual.EmailTemplate)
			require.Equal(t, tc.expected.CreatedDate, actual.CreatedDate)
			require.JSONEq(t, tc.expected.Payload, actual.Payload)
		})
	}
}
