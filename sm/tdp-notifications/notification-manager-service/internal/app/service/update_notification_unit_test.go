package service

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"
	"github.com/samber/lo"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	nmerrors "github.com/tucowsinc/tdp-notifications/notification-manager-service/internal/app/errors"
	"github.com/tucowsinc/tdp-notifications/notification-manager-service/internal/app/model"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
	mocksrepo "github.com/tucowsinc/tdp-shared-go/repository/v3/mocks"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type serviceMocks struct {
	t                 *testing.T
	subDB             *database.MockDatabase
	vNotificationRepo *mocksrepo.IRepository[*model.VNotification]
	logger            logger.ILogger
}

func newServiceMocks(t *testing.T) (s *Service, m serviceMocks) {
	t.Helper()
	m = serviceMocks{
		t:                 t,
		subDB:             database.NewMockDatabase(t),
		vNotificationRepo: mocksrepo.NewIRepository[*model.VNotification](t),
		logger:            &logger.MockLogger{},
	}

	s = &Service{
		vnotificationRepo: m.vNotificationRepo,
		subDB:             m.subDB,
		logger:            m.logger,
	}
	return

}

func TestUpdateNotificationStatus(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	tests := []struct {
		name       string
		req        *datamanager.Notification
		mocksF     func(m serviceMocks)
		requireErr require.ErrorAssertionFunc
	}{
		{
			name: "happy path",
			req: &datamanager.Notification{
				TenantCustomerId: lo.ToPtr(uuid.New().String()),
				WebhookUrl:       lo.ToPtr("https://webhook.com"),
				SigningSecret:    lo.ToPtr("secret"),
				Status:           datamanager.DeliveryStatus_PUBLISHED,
				StatusReason:     "some silly reason",
				Data:             lo.Must(anypb.New(&structpb.Struct{})),
				CreatedDate:      timestamppb.Now(),
			},
			mocksF: func(m serviceMocks) {
				m.vNotificationRepo.On("Update",
					ctx,
					m.subDB,
					mock.AnythingOfType("*model.VNotification")).
					Return(int64(1), nil).Times(1)
			},
			requireErr: require.NoError,
		},
		{
			name: "error path - status is not published or failed",
			req: &datamanager.Notification{
				TenantCustomerId: lo.ToPtr(uuid.New().String()),
				WebhookUrl:       lo.ToPtr("https://webhook.com"),
				SigningSecret:    lo.ToPtr("secret"),
				Status:           datamanager.DeliveryStatus_PUBLISHING,
				StatusReason:     "some silly reason",
			},
			requireErr: func(t require.TestingT, err error, msgAndArgs ...interface{}) {
				expected := nmerrors.ErrInvalidFinalStatus
				require.Truef(t, errors.Is(err, expected), "expected error %v, got %v", expected, err)
			},
		},
		{
			name: "error path - database failure",
			req: &datamanager.Notification{
				TenantCustomerId: lo.ToPtr(uuid.New().String()),
				WebhookUrl:       lo.ToPtr("https://webhook.com"),
				SigningSecret:    lo.ToPtr("secret"),
				Status:           datamanager.DeliveryStatus_PUBLISHED,
				StatusReason:     "some silly reason",
				Data:             lo.Must(anypb.New(&structpb.Struct{})),
				CreatedDate:      timestamppb.Now(),
			},
			mocksF: func(m serviceMocks) {
				m.vNotificationRepo.On("Update",
					ctx,
					m.subDB,
					mock.AnythingOfType("*model.VNotification")).
					Return(int64(0), nmerrors.ErrDatabaseUpdateFailed).Times(1)
			},
			requireErr: func(t require.TestingT, err error, msgAndArgs ...interface{}) {
				expected := nmerrors.ErrDatabaseUpdateFailed
				require.Truef(t, errors.Is(err, expected), "expected error %v, got %v", expected, err)
			},
		},
		{
			name: "error path - no notification updated",
			req: &datamanager.Notification{
				TenantCustomerId: lo.ToPtr(uuid.New().String()),
				WebhookUrl:       lo.ToPtr("https://webhook.com"),
				SigningSecret:    lo.ToPtr("secret"),
				Status:           datamanager.DeliveryStatus_PUBLISHED,
				StatusReason:     "some silly reason",
				Data:             lo.Must(anypb.New(&structpb.Struct{})),
				CreatedDate:      timestamppb.Now(),
			},
			mocksF: func(m serviceMocks) {
				m.vNotificationRepo.On("Update",
					ctx,
					m.subDB,
					mock.AnythingOfType("*model.VNotification")).
					Return(int64(0), nil).Times(1)
			},
			requireErr: func(t require.TestingT, err error, msgAndArgs ...interface{}) {
				expected := nmerrors.ErrNotFound
				require.Truef(t, errors.Is(err, expected), "expected error %v, got %v", expected, err)
			},
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			s, m := newServiceMocks(t)
			if tc.mocksF != nil {
				tc.mocksF(m)
			}
			err := s.UpdateNotificationStatus(ctx, tc.req)
			tc.requireErr(t, err)

		})
	}
}
