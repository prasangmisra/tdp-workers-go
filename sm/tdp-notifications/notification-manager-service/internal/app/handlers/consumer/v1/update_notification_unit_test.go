package v1

import (
	"context"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"github.com/tucowsinc/tdp-notifications/notification-manager-service/internal/app/config"
	nmerrors "github.com/tucowsinc/tdp-notifications/notification-manager-service/internal/app/errors"
	handlersmock "github.com/tucowsinc/tdp-notifications/notification-manager-service/internal/app/mock/rest/handlers"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"google.golang.org/protobuf/proto"
)

func TestUpdateNotificationStatus(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name       string
		msg        proto.Message
		mocksF     func(*handlersmock.IService, *mocks.MockMessageBusServer, *mocks.MockMessageBus)
		requireErr require.ErrorAssertionFunc
	}{
		{
			name:       "happy path",
			msg:        &datamanager.Notification{},
			requireErr: require.NoError,
			mocksF: func(srvc *handlersmock.IService, mbsrvr *mocks.MockMessageBusServer, mockedBus *mocks.MockMessageBus) {
				ctx := context.Background()
				mbsrvr.On("Reply", map[string]interface{}(nil)).
					Return(nil).Times(1)
				mbsrvr.On("Context").
					Return(ctx).Times(1)
				srvc.On("UpdateNotificationStatus", ctx, mock.Anything).
					Return(nil).Times(1)
			},
		},
		{
			name:       "error path - invalid notiifcation - reply with BAD_REQUEST",
			msg:        &datamanager.Notification{},
			requireErr: require.Error,
			mocksF: func(srvc *handlersmock.IService, mbsrvr *mocks.MockMessageBusServer, mockedBus *mocks.MockMessageBus) {
				ctx := context.Background()
				mbsrvr.On("Context").
					Return(ctx).Times(1)
				srvc.On("UpdateNotificationStatus", ctx, mock.Anything).
					Return(nmerrors.ErrInvalidNotification).Times(1)
			},
		},
		{
			name:       "error path - no notification to update - reply with NOT_FOUND",
			msg:        &datamanager.Notification{},
			requireErr: require.Error,
			mocksF: func(srvc *handlersmock.IService, mbsrvr *mocks.MockMessageBusServer, mockedBus *mocks.MockMessageBus) {
				ctx := context.Background()
				mbsrvr.On("Context").
					Return(ctx).Times(1)
				srvc.On("UpdateNotificationStatus", ctx, mock.Anything).
					Return(nmerrors.ErrNotFound).Times(1)
			},
		},
		{
			name:       "error path - database update failed - reply with FAILED OPERATION",
			msg:        &datamanager.Notification{},
			requireErr: require.Error,
			mocksF: func(srvc *handlersmock.IService, mbsrvr *mocks.MockMessageBusServer, mockedBus *mocks.MockMessageBus) {
				ctx := context.Background()
				mbsrvr.On("Context").
					Return(ctx).Times(1)
				srvc.On("UpdateNotificationStatus", ctx, mock.Anything).
					Return(nmerrors.ErrDatabaseUpdateFailed).Times(1)
			},
		},
		{
			name:       "warn path - invalid notification status. don't error out, just log",
			msg:        &datamanager.Notification{},
			requireErr: require.NoError,
			mocksF: func(srvc *handlersmock.IService, mbsrvr *mocks.MockMessageBusServer, mockedBus *mocks.MockMessageBus) {
				ctx := context.Background()
				mbsrvr.On("Context").
					Return(ctx).Times(1)
				srvc.On("UpdateNotificationStatus", ctx, mock.Anything).
					Return(nmerrors.ErrInvalidFinalStatus).Times(1)
			},
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			srvc := handlersmock.NewIService(t)
			mockedBus := &mocks.MockMessageBus{}
			mbsrvr := &mocks.MockMessageBusServer{}
			router := NewHandler(srvc, &logger.MockLogger{}, config.Config{}, mockedBus)

			if tc.mocksF != nil {
				tc.mocksF(srvc, mbsrvr, mockedBus)
			}

			err := router.UpdateNotificationStatusHandler(mbsrvr, tc.msg)
			tc.requireErr(t, err)
		})
	}

}
