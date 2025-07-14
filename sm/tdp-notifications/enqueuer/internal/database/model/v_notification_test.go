package model

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/samber/lo"
	"github.com/stretchr/testify/assert"
	"github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestVNotification_ToWebhookProto(t *testing.T) {
	t.Parallel()

	sampleJson := "{\"foo\": \"bar\"}"
	var unmarshalled map[string]interface{}
	err := json.Unmarshal([]byte(sampleJson), &unmarshalled)
	assert.NoError(t, err)

	structValue, err := structpb.NewStruct(unmarshalled)
	assert.NoError(t, err)
	converted, err := anypb.New(structValue)
	assert.NoError(t, err)

	tests := []struct {
		name     string
		input    *VNotification
		expected *datamanager.Notification
	}{
		{
			name: "successful conversion",
			input: &VNotification{
				ID:               lo.ToPtr("123"),
				Type:             lo.ToPtr("email"),
				TenantID:         lo.ToPtr("tenant_1"),
				TenantCustomerID: lo.ToPtr("customer_1"),
				WebhookURL:       lo.ToPtr("http://example.com/webhook"),
				SigningSecret:    lo.ToPtr("secret"),
				CreatedDate:      lo.ToPtr(time.Date(2023, 10, 1, 0, 0, 0, 0, time.UTC)),
				Status:           lo.ToPtr("received"),
				Payload:          lo.ToPtr("{\"foo\": \"bar\"}"),
			},
			expected: &datamanager.Notification{
				Id:               "123",
				Type:             "email",
				TenantId:         "tenant_1",
				TenantCustomerId: proto.String("customer_1"),
				WebhookUrl:       proto.String("http://example.com/webhook"),
				SigningSecret:    proto.String("secret"),
				CreatedDate:      timestamppb.New(time.Date(2023, 10, 1, 0, 0, 0, 0, time.UTC)),
				Status:           datamanager.DeliveryStatus_RECEIVED,
				Data:             converted,
			},
		},
		{
			name: "unsupported status",
			input: &VNotification{
				ID:               lo.ToPtr("124"),
				Type:             lo.ToPtr("webhook"),
				TenantID:         lo.ToPtr("tenant_2"),
				TenantCustomerID: lo.ToPtr("customer_2"),
				WebhookURL:       lo.ToPtr("http://example.com/webhook2"),
				SigningSecret:    lo.ToPtr("secret2"),
				CreatedDate:      lo.ToPtr(time.Date(2023, 10, 2, 0, 0, 0, 0, time.UTC)),
				Status:           lo.ToPtr("unsupported"),
				Payload:          lo.ToPtr("{\"foo\": \"bar\"}"),
			},
			expected: &datamanager.Notification{
				Id:               "124",
				Type:             "webhook",
				TenantId:         "tenant_2",
				TenantCustomerId: proto.String("customer_2"),
				WebhookUrl:       proto.String("http://example.com/webhook2"),
				SigningSecret:    proto.String("secret2"),
				CreatedDate:      timestamppb.New(time.Date(2023, 10, 2, 0, 0, 0, 0, time.UTC)),
				Status:           datamanager.DeliveryStatus_UNSUPPORTED,
				Data:             converted,
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			result, err := tt.input.ToWebhookProto()
			assert.NoError(t, err)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestVNotification_ToEmailProto(t *testing.T) {
	t.Parallel()

	testDate := (time.Date(2023, 10, 2, 0, 0, 0, 0, time.UTC))
	validPayload := `
						{
							"data": {
								"foo": "bar"
							},
							"envelope": {
								"subject": "Test email notification",
								"to_address": [
									{
										"name": "Gary Ng",
										"email": "foo_bar@tucowsinc.com"
									}
								]
							}
						}`
	payloadNoEnvelope := `
						{
							"data": {
								"foo": "bar"
							}
						}`
	payloadNoData := `
								{
									"envelope": {
										"subject": "Test email notification",
										"to_address": [
											{
												"name": "Gary Ng",
												"email": "foo_bar@tucowsinc.com"
											}
										]
									}
								}`
	payloadDataNotAMap := `
							{
								"data": "bar",
								"envelope": {
									"subject": "Test email notification",
									"to_address": [
										{
											"name": "Gary Ng",
											"email": "foo_bar@tucowsinc.com"
										}
									]
								}
							}`

	// Create the expected ouput "data" field on the email proto message
	// Note that this should be the contents of the "data" in validPayload

	payloadMap := map[string]interface{}{"foo": "bar"}
	structVal, err := structpb.NewStruct(payloadMap)
	assert.NoError(t, err)
	expectedDataVal, err := anypb.New(structVal)
	assert.NoError(t, err)
	testTemplate := "some-template-code"

	// Create the expected emailNotification
	expectedEmailNotification := &datamanager.EmailNotification{}
	//Create the expected "envelope" for the expectedEmailNotification
	var validPayloadJson map[string]interface{}
	json.Unmarshal([]byte(validPayload), &validPayloadJson)
	envelopeJson := validPayloadJson["envelope"]
	envelopeJsonBytes, err := json.Marshal(envelopeJson)
	assert.NoError(t, err)
	expectedEnvelope := &common.EmailEnvelope{}
	protojson.Unmarshal(envelopeJsonBytes, expectedEnvelope)

	// Create a payload with a nil data field
	// This is to test the error case where the payload is nil

	expectedEmailNotification = &datamanager.EmailNotification{
		Envelope: expectedEnvelope,
		Template: testTemplate,
	}

	tests := []struct {
		name             string
		input            *VNotification
		expectedResponse proto.Message
		expectError      bool
		errorMessage     string
	}{
		{
			name:         "error - an uninitialized vnotification",
			input:        &VNotification{},
			expectError:  true,
			errorMessage: "channel type is nil for notification ",
		},
		{
			name: "error - some missing fields",
			input: &VNotification{
				NotificationID: lo.ToPtr("123"),
				ChannelType:    lo.ToPtr("email"),
				EmailTemplate:  lo.ToPtr("some-template"),
				Payload:        lo.ToPtr(validPayload),
			},
			expectError:  true,
			errorMessage: "ID is nil for notification 123",
		},
		{
			name: "channeltype is nil",
			input: &VNotification{
				NotificationID: lo.ToPtr("123"),
			},
			expectError:  true,
			errorMessage: "channel type is nil for notification 123",
		},
		{
			name: "template nil",
			input: &VNotification{
				NotificationID: lo.ToPtr("123"),
				ChannelType:    lo.ToPtr("email"),
			},
			expectError:  true,
			errorMessage: "email template is nil for notification 123",
		},
		{
			name: "malformed payload",
			input: &VNotification{
				NotificationID: lo.ToPtr("123"),
				ChannelType:    lo.ToPtr("email"),
				EmailTemplate:  lo.ToPtr("some-template"),
				Payload:        lo.ToPtr("{malformed-json"),
			},
			expectError:  true,
			errorMessage: "failed to unmarshal payload for notification 123: invalid character 'm' looking for beginning of object key string",
		},
		{
			name: "error - nil payload",
			input: &VNotification{
				NotificationID: lo.ToPtr("123"),
				ChannelType:    lo.ToPtr("email"),
				EmailTemplate:  lo.ToPtr("some-template"),
				Payload:        nil,
			},
			expectError:  true,
			errorMessage: "payload is nil for notification 123",
		},
		{
			name: "error - nil data",
			input: &VNotification{
				NotificationID: lo.ToPtr("123"),
				ChannelType:    lo.ToPtr("email"),
				EmailTemplate:  lo.ToPtr("some-template"),
				Payload:        &payloadNoData,
			},
			expectError:  true,
			errorMessage: "data is nil for notification 123",
		},
		{
			name: "error - payload data not a map",
			input: &VNotification{
				NotificationID: lo.ToPtr("123"),
				ChannelType:    lo.ToPtr("email"),
				EmailTemplate:  lo.ToPtr("some-template"),
				Payload:        &payloadDataNotAMap,
			},
			expectError:  true,
			errorMessage: "data is not a map for notification 123",
		},
		{
			name: "error - payload - no envelope",
			input: &VNotification{
				NotificationID: lo.ToPtr("123"),
				ChannelType:    lo.ToPtr("email"),
				EmailTemplate:  lo.ToPtr("some-template"),
				Payload:        &payloadNoEnvelope,
			},
			expectError:  true,
			errorMessage: "envelope is nil for notification 123",
		},

		{
			name: "success",
			input: &VNotification{
				ID:               lo.ToPtr("124"),
				Type:             lo.ToPtr("email"),
				TenantID:         lo.ToPtr("tenant_2"),
				TenantCustomerID: lo.ToPtr("customer_2"),
				Status:           lo.ToPtr("received"),
				ChannelType:      lo.ToPtr("email"),
				EmailTemplate:    lo.ToPtr(testTemplate),
				Payload:          lo.ToPtr(validPayload),
				NotificationID:   lo.ToPtr("notif-123"),
				CreatedDate:      lo.ToPtr(testDate),
			},
			expectError: false,
			expectedResponse: &datamanager.Notification{
				Id:                  "124",
				Type:                "email",
				TenantId:            "tenant_2",
				TenantCustomerId:    proto.String("customer_2"),
				Status:              datamanager.DeliveryStatus_RECEIVED,
				Data:                expectedDataVal,
				CreatedDate:         timestamppb.New(testDate),
				NotificationDetails: &datamanager.Notification_EmailNotification{EmailNotification: expectedEmailNotification},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			result, err := tt.input.ToEmailProto()
			if tt.expectError {
				assert.Error(t, err)
				assert.Equal(t, tt.errorMessage, err.Error())
				assert.Nil(t, result)
			} else {
				assert.NoError(t, err)
				assert.NotNil(t, result)
				assert.Equal(t, tt.expectedResponse, result)
			}
		})
	}
}
