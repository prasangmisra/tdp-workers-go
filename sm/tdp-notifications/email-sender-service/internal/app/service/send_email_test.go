package service

import (
	"context"
	"errors"
	"github.com/stretchr/testify/mock"
	"net/mail"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
	mbmocks "github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message/common"
	proto "github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"github.com/tucowsinc/tdp-notifications/email-sender-service/internal/app/mocks"
	"github.com/tucowsinc/tdp-notifications/email-sender-service/internal/app/model/esender"
	"github.com/tucowsinc/tdp-shared-go/logger"
	gproto "google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"
)

func TestSendEmail(t *testing.T) {
	t.Parallel()
	const statusQ = "final_status_queue"
	ctx := context.Background()

	//Create some bad "data" for the template.  In this case, just the number 44 wrapped in an Any

	bogusAnyData := func() *anypb.Any {
		anyData, _ := anypb.New(&structpb.Value{
			Kind: &structpb.Value_NumberValue{NumberValue: 44},
		})
		return anyData
	}()

	tests := []struct {
		name         string
		notification *proto.Notification
		msgHeaders   map[string]any
		mocksF       func(*mbmocks.MockMessageBus, *mocks.EmailSender)
		requireErr   require.ErrorAssertionFunc
	}{
		{
			name: "failure - failure to render template",
			notification: &proto.Notification{
				NotificationDetails: &proto.Notification_EmailNotification{
					EmailNotification: &proto.EmailNotification{
						Envelope: &common.EmailEnvelope{
							Subject:     "subject",
							FromAddress: &common.Address{Email: "from@email.com"},
							ToAddress:   []*common.Address{{Email: "to@email.com"}},
						},
						Template: "<html", // This incomplete HTML tag will cause a rendering error
					},
				},
				Data: nil,
			},
			mocksF: func(mb *mbmocks.MockMessageBus, eSender *mocks.EmailSender) {
				mb.On("Send",
					ctx,
					statusQ,
					mock.MatchedBy(func(actual *proto.Notification) bool {
						if !strings.Contains(actual.GetStatusReason(), errorRenderingTemplateReason) {
							return false
						}
						expected := &proto.Notification{
							Status:       proto.DeliveryStatus_FAILED,
							StatusReason: actual.GetStatusReason(),
							NotificationDetails: &proto.Notification_EmailNotification{
								EmailNotification: &proto.EmailNotification{
									Envelope: &common.EmailEnvelope{
										Subject:     "subject",
										FromAddress: &common.Address{Email: "from@email.com"},
										ToAddress:   []*common.Address{{Email: "to@email.com"}},
									},
									Template: "<html",
								},
							},
							Data: nil,
						}
						return gproto.Equal(expected, actual)
					}),
					map[string]any(nil)).
					Return("", nil).Once()
			},
			requireErr: require.NoError,
		},
		{
			name: "failure - bad notification template data",
			notification: &proto.Notification{
				NotificationDetails: &proto.Notification_EmailNotification{
					EmailNotification: &proto.EmailNotification{
						Envelope: &common.EmailEnvelope{
							Subject:     "subject",
							FromAddress: &common.Address{Email: "from@email.com"},
							ToAddress:   []*common.Address{{Email: "to@email.com"}},
						},
						Template: "body",
					},
				},
				Data: bogusAnyData,
			},
			mocksF: func(mb *mbmocks.MockMessageBus, eSender *mocks.EmailSender) {
				mb.On("Send",
					ctx,
					statusQ,
					mock.MatchedBy(func(actual *proto.Notification) bool {
						if !strings.Contains(actual.GetStatusReason(), errorDecodingDataReason) {
							return false
						}
						expected := &proto.Notification{
							Status:       proto.DeliveryStatus_FAILED,
							StatusReason: actual.GetStatusReason(),
							NotificationDetails: &proto.Notification_EmailNotification{
								EmailNotification: &proto.EmailNotification{
									Envelope: &common.EmailEnvelope{
										Subject:     "subject",
										FromAddress: &common.Address{Email: "from@email.com"},
										ToAddress:   []*common.Address{{Email: "to@email.com"}},
									},
									Template: "body",
								},
							},
							Data: bogusAnyData,
						}
						return gproto.Equal(expected, actual)
					}),
					map[string]any(nil)).
					Return("", nil).Once()

				mb.On("Send",
					ctx,
					statusQ,
					mock.MatchedBy(func(actual *proto.Notification) bool {
						if !strings.Contains(actual.GetStatusReason(), errorDecodingDataReason) {
							return false
						}
						expected := &proto.Notification{
							Status:       proto.DeliveryStatus_FAILED,
							StatusReason: actual.GetStatusReason(),
							NotificationDetails: &proto.Notification_EmailNotification{
								EmailNotification: &proto.EmailNotification{
									Envelope: &common.EmailEnvelope{
										Subject:     "subject",
										FromAddress: &common.Address{Email: "from@email.com"},
										ToAddress:   []*common.Address{{Email: "to@email.com"}},
									},
									Template: "body",
								},
							},
							Data: bogusAnyData,
						}
						return gproto.Equal(expected, actual)
					}),
					map[string]any(nil)).
					Return("", nil).Once()
			},
			requireErr: require.NoError,
		},
		{
			name:         "failure - email notification is empty",
			notification: &proto.Notification{},
			msgHeaders:   map[string]any{"tenant-customer-id": "test-tenant-customer-id"},
			mocksF: func(mb *mbmocks.MockMessageBus, eSender *mocks.EmailSender) {
				mb.On("Send", ctx, statusQ,
					&proto.Notification{Status: proto.DeliveryStatus_FAILED, StatusReason: emptyNotificationReason},
					map[string]any{"tenant-customer-id": "test-tenant-customer-id"}).Return("", nil).Once()
			},
			requireErr: require.NoError,
		},
		{
			name:         "failure - error on publishing",
			notification: &proto.Notification{},
			mocksF: func(mb *mbmocks.MockMessageBus, eSender *mocks.EmailSender) {
				mb.On("Send", ctx, statusQ,
					&proto.Notification{Status: proto.DeliveryStatus_FAILED, StatusReason: emptyNotificationReason},
					map[string]any(nil)).Return("", errors.New("publishing error")).Once()
			},
			requireErr: require.Error,
		},
		{
			name: "failure - unable to send email",
			notification: &proto.Notification{
				NotificationDetails: &proto.Notification_EmailNotification{
					EmailNotification: &proto.EmailNotification{
						Envelope: &common.EmailEnvelope{
							Subject:     "subject",
							FromAddress: &common.Address{Email: "from@email.com"},
							ToAddress:   []*common.Address{{Email: "to@email.com"}},
						},
						Template: "body",
					},
				},
			},
			mocksF: func(mb *mbmocks.MockMessageBus, eSender *mocks.EmailSender) {
				eSender.On("SendEmail", ctx,
					esender.Message{Subject: "subject", Body: "body"},
					mail.Address{Address: "from@email.com"},
					mail.Address{},
					esender.Addresses{{Address: "to@email.com"}},
					esender.Addresses{},
					esender.Addresses{},
				).Return(errors.New("error sending email")).Once()

				mb.On("Send", ctx, statusQ,
					mock.MatchedBy(func(actual *proto.Notification) bool {
						if !strings.Contains(actual.GetStatusReason(), errorSendingEmailReason) {
							return false
						}

						expected := &proto.Notification{
							Status:       proto.DeliveryStatus_FAILED,
							StatusReason: actual.GetStatusReason(),
							NotificationDetails: &proto.Notification_EmailNotification{
								EmailNotification: &proto.EmailNotification{
									Envelope: &common.EmailEnvelope{
										Subject:     "subject",
										FromAddress: &common.Address{Email: "from@email.com"},
										ToAddress:   []*common.Address{{Email: "to@email.com"}},
									},
									Template: "body",
								},
							},
						}
						return gproto.Equal(expected, actual)
					}),
					map[string]any(nil)).
					Return("", nil).Once()
			},
			requireErr: require.NoError,
		},
		{
			name: "success - happy path",
			notification: &proto.Notification{
				NotificationDetails: &proto.Notification_EmailNotification{
					EmailNotification: &proto.EmailNotification{
						Envelope: &common.EmailEnvelope{
							Subject:     "subject",
							FromAddress: &common.Address{Email: "from@email.com"},
							ToAddress:   []*common.Address{{Email: "to@email.com"}},
						},
						Template: "body",
					},
				},
			},
			mocksF: func(mb *mbmocks.MockMessageBus, eSender *mocks.EmailSender) {
				eSender.On("SendEmail", ctx,
					esender.Message{Subject: "subject", Body: "body"},
					mail.Address{Address: "from@email.com"},
					mail.Address{},
					esender.Addresses{{Address: "to@email.com"}},
					esender.Addresses{},
					esender.Addresses{},
				).Return(nil).Once()

				mb.On("Send", ctx, statusQ,
					&proto.Notification{
						Status:       proto.DeliveryStatus_PUBLISHED,
						StatusReason: successReason,
						NotificationDetails: &proto.Notification_EmailNotification{
							EmailNotification: &proto.EmailNotification{
								Envelope: &common.EmailEnvelope{
									Subject:     "subject",
									FromAddress: &common.Address{Email: "from@email.com"},
									ToAddress:   []*common.Address{{Email: "to@email.com"}},
								},
								Template: "body",
							},
						},
					},
					map[string]any(nil)).
					Return("", nil).Once()
			},
			requireErr: require.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			eSender := mocks.NewEmailSender(t)
			bus := new(mbmocks.MockMessageBus)
			tt.mocksF(bus, eSender)

			s := New(&logger.MockLogger{}, eSender, bus, statusQ)
			err := s.SendEmail(ctx, tt.notification, tt.msgHeaders)
			tt.requireErr(t, err)
		})
	}
}
func TestDecodeAnyToMap(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name        string
		input       *anypb.Any
		expected    map[string]interface{}
		expectError bool
	}{
		{
			name:        "nil input",
			input:       nil,
			expected:    map[string]interface{}{},
			expectError: false,
		},
		{
			name: "valid struct input",
			input: func() *anypb.Any {
				structData, _ := structpb.NewStruct(map[string]interface{}{
					"key1": "value1",
					"key2": 123.0,
					"key3": true,
				})
				anyData, _ := anypb.New(structData)
				return anyData
			}(),
			expected: map[string]interface{}{
				"key1": "value1",
				"key2": 123.0,
				"key3": true,
			},
			expectError: false,
		},
		{
			name: "invalid input",
			input: func() *anypb.Any {
				return &anypb.Any{TypeUrl: "invalid", Value: []byte("invalid")}
			}(),
			expected:    nil,
			expectError: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			result, err := decodeAnyToMap(tt.input)
			if tt.expectError {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				require.Equal(t, tt.expected, result)
			}
		})
	}
}
