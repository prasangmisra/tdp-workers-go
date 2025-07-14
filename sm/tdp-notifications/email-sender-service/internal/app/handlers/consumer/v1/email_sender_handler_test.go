package v1

import (
	"context"
	"errors"
	"github.com/stretchr/testify/require"
	mbmocks "github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"github.com/tucowsinc/tdp-notifications/email-sender-service/internal/app/mocks"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"google.golang.org/protobuf/proto"
	"testing"
)

func TestEmailSenderHandler(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name       string
		msg        proto.Message
		mocksF     func(mbs *mbmocks.MockMessageBusServer, s *mocks.Service)
		requireErr require.ErrorAssertionFunc
	}{
		{
			name:       "invalid proto message",
			requireErr: require.Error,
		},
		{
			name: "error on sending email",
			msg:  &datamanager.Notification{},
			mocksF: func(mbs *mbmocks.MockMessageBusServer, s *mocks.Service) {
				ctx := context.Background()
				headers := map[string]any{"tenant-customer-id": "test-tenant-customer-id"}
				mbs.On("Context").Return(ctx).Once()
				mbs.On("Headers").Return(headers).Once()
				s.On("SendEmail", ctx, &datamanager.Notification{}, headers).
					Return(errors.New("internal error")).Once()
			},
			requireErr: require.Error,
		},
		{
			name: "happy path",
			msg:  &datamanager.Notification{},
			mocksF: func(mbs *mbmocks.MockMessageBusServer, s *mocks.Service) {
				ctx := context.Background()
				headers := map[string]any{"tenant-customer-id": "test-tenant-customer-id"}
				mbs.On("Context").Return(ctx).Once()
				mbs.On("Headers").Return(headers).Once()
				s.On("SendEmail", ctx, &datamanager.Notification{}, headers).
					Return(nil).Once()
			},
			requireErr: require.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			mbs := new(mbmocks.MockMessageBusServer)
			service := mocks.NewService(t)
			if tt.mocksF != nil {
				tt.mocksF(mbs, service)
			}

			h := NewHandler(service, &logger.MockLogger{})
			err := h.EmailSenderHandler(mbs, tt.msg)
			tt.requireErr(t, err)
		})
	}
}
