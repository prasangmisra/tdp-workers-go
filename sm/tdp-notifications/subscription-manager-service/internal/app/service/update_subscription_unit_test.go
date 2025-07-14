package service

import (
	"context"
	"errors"
	"testing"

	smerrors "github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/errors"
	"github.com/tucowsinc/tdp-shared-go/repository/v3"

	"github.com/google/uuid"
	"github.com/lib/pq"
	"github.com/samber/lo"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	proto "github.com/tucowsinc/tdp-messages-go/message/subscription"
	"github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/model"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
)

func TestUpdateSubscription(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	tenantCustomerID := uuid.NewString()

	tests := []struct {
		name   string
		req    *proto.SubscriptionUpdateRequest
		mocksF func(m serviceMocks)

		expectedResp *proto.SubscriptionUpdateResponse
		requireErr   require.ErrorAssertionFunc
	}{
		{
			name:       "error invalid request",
			req:        &proto.SubscriptionUpdateRequest{},
			requireErr: require.Error,
		},
		{
			name: "error while getting notification type id to add",
			req: &proto.SubscriptionUpdateRequest{
				AddNotificationTypes: []string{"100"},
			},
			mocksF: func(m serviceMocks) {
				m.notificationTypeLT.On("GetIdByName", "100").
					Return("").Once()
			},
			requireErr: require.Error,
		},
		{
			name: "error while getting notification type id to remove",
			req: &proto.SubscriptionUpdateRequest{
				RemNotificationTypes: []string{"100"},
			},
			mocksF: func(m serviceMocks) {
				m.notificationTypeLT.On("GetIdByName", "100").
					Return("").Once()
			},
			requireErr: require.Error,
		},
		{
			name: "error getting TenantID",
			req: &proto.SubscriptionUpdateRequest{
				Description: lo.ToPtr("test"),
			},
			mocksF: func(m serviceMocks) {
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, "", mock.AnythingOfType("repository.OptionsFunc")).
					Return((*model.VTenantCustomer)(nil), errors.New("db error")).Once()
			},
			requireErr: require.Error,
		},
		{
			name: "error on updating subscription",
			req: &proto.SubscriptionUpdateRequest{
				TenantCustomerId: tenantCustomerID,
				Description:      lo.ToPtr("test"),
			},
			mocksF: func(m serviceMocks) {
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, tenantCustomerID, mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.NewString())}, nil).Once()

				tx := m.subDB.OnTransaction(m.t, database.WithRollback(nil))

				{ // tx block, fail here
					m.subscriptionViewRepo.On("Update", ctx, tx, mock.Anything,
						mock.AnythingOfType("repository.OptionsFunc"), mock.AnythingOfType("repository.OptionsFunc")).
						Return(int64(0), errors.New("db error")).Times(1)
				}
			},
			requireErr: require.Error,
		},
		{
			name: "subscription not found on update",
			req: &proto.SubscriptionUpdateRequest{
				TenantCustomerId: tenantCustomerID,
				Description:      lo.ToPtr("test"),
			},
			mocksF: func(m serviceMocks) {
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, tenantCustomerID, mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.NewString())}, nil).Once()

				tx := m.subDB.OnTransaction(m.t, database.WithRollback(nil))

				{ // tx block, pass here
					m.subscriptionViewRepo.On("Update", ctx, tx, mock.Anything,
						mock.AnythingOfType("repository.OptionsFunc"), mock.AnythingOfType("repository.OptionsFunc")).
						Return(int64(0), nil).Times(1)
				}
			},
			requireErr: func(t require.TestingT, err error, i ...interface{}) {
				require.ErrorIs(t, err, smerrors.ErrNotFound)
			},
		},
		{
			name: "successfully update subscription with only description",
			req: &proto.SubscriptionUpdateRequest{
				TenantCustomerId: tenantCustomerID,
				Description:      lo.ToPtr("test"),
			},
			mocksF: func(m serviceMocks) {
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, tenantCustomerID, mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.NewString())}, nil).Once()

				tx := m.subDB.OnTransaction(m.t, database.WithCommit(nil))

				{ // tx block, pass here
					m.subscriptionViewRepo.On("Update", ctx, tx, mock.Anything,
						mock.AnythingOfType("repository.OptionsFunc"), mock.AnythingOfType("repository.OptionsFunc")).
						Return(int64(1), nil).Times(1)
				}
			},
			requireErr: require.NoError,
			expectedResp: &proto.SubscriptionUpdateResponse{
				Subscription: &proto.SubscriptionDetailsResponse{
					Description: lo.ToPtr("test"),
				},
			},
		},
		{
			name: "error on count subscriptions while updating notification types",
			req: &proto.SubscriptionUpdateRequest{
				TenantCustomerId:     tenantCustomerID,
				AddNotificationTypes: []string{"CONTACT_CREATED"},
			},
			mocksF: func(m serviceMocks) {
				ntName := "contact_created"
				m.notificationTypeLT.On("GetIdByName", ntName).Return(uuid.NewString()).Once()

				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, tenantCustomerID, mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.NewString())}, nil).Once()

				tx := m.subDB.OnTransaction(m.t, database.WithRollback(nil))

				{ // tx block - fail here
					m.subscriptionViewRepo.On("Count", ctx, tx, mock.Anything).
						Return(int64(0), errors.New("db error")).Once()
				}
			},
			requireErr: require.Error,
		},
		{
			name: "error - 0 subscription found while updating notification type",
			req: &proto.SubscriptionUpdateRequest{
				TenantCustomerId:     tenantCustomerID,
				AddNotificationTypes: []string{"CONTACT_UPDATED"},
			},
			mocksF: func(m serviceMocks) {
				ntName := "contact_updated"
				m.notificationTypeLT.On("GetIdByName", ntName).Return(uuid.NewString()).Once()

				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, tenantCustomerID, mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.NewString())}, nil).Once()

				tx := m.subDB.OnTransaction(m.t, database.WithRollback(nil))

				{ // tx block - fail here
					m.subscriptionViewRepo.On("Count", ctx, tx, mock.Anything).
						Return(int64(0), nil).Once()
				}
			},
			requireErr: func(t require.TestingT, err error, i ...interface{}) {
				require.ErrorIs(t, err, smerrors.ErrNotFound)
			},
		},
		{
			name: "error while creating notification type",
			req: &proto.SubscriptionUpdateRequest{
				TenantCustomerId:     tenantCustomerID,
				AddNotificationTypes: []string{"CONTACT_UPDATED"},
			},
			mocksF: func(m serviceMocks) {
				ntName := "contact_updated"
				m.notificationTypeLT.On("GetIdByName", ntName).Return(uuid.NewString()).Once()

				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, tenantCustomerID, mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.NewString())}, nil).Once()

				tx := m.subDB.OnTransaction(m.t, database.WithRollback(nil))

				{ // tx block
					m.subscriptionViewRepo.On("Count", ctx, tx, mock.Anything).
						Return(int64(1), nil).Once()

					// fail here
					m.subscriptionNotificationTypeRepo.On("CreateBatch", ctx, tx, mock.Anything, mock.AnythingOfType("repository.OptionsFunc")).
						Return(int64(0), errors.New("db error")).Once()
				}
			},
			requireErr: require.Error,
		},
		{
			name: "error getting subscription after update",
			req: &proto.SubscriptionUpdateRequest{
				TenantCustomerId:     tenantCustomerID,
				AddNotificationTypes: []string{"CONTACT_UPDATED"},
			},
			mocksF: func(m serviceMocks) {
				ntName := "contact_updated"
				m.notificationTypeLT.On("GetIdByName", ntName).Return(uuid.NewString()).Once()

				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, tenantCustomerID, mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.NewString())}, nil).Once()

				tx := m.subDB.OnTransaction(m.t, database.WithRollback(nil))

				{ // tx block
					m.subscriptionViewRepo.On("Count", ctx, tx, mock.Anything).
						Return(int64(1), nil).Once()
					m.subscriptionNotificationTypeRepo.On("CreateBatch", ctx, tx, mock.Anything, mock.AnythingOfType("repository.OptionsFunc")).
						Return(int64(1), nil).Once()

					// fail here
					m.subscriptionViewRepo.On("GetByID", ctx, tx, "", mock.AnythingOfType("repository.OptionsFunc")).
						Return((*model.VSubscription)(nil), errors.New("db error")).Once()
				}
			},
			requireErr: require.Error,
		},
		{
			name: "error - received NotFound error while getting subscription after update",
			req: &proto.SubscriptionUpdateRequest{
				TenantCustomerId:     tenantCustomerID,
				AddNotificationTypes: []string{"CONTACT_UPDATED"},
			},
			mocksF: func(m serviceMocks) {
				ntName := "contact_updated"
				m.notificationTypeLT.On("GetIdByName", ntName).Return(uuid.NewString()).Once()

				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, tenantCustomerID, mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.NewString())}, nil).Once()

				tx := m.subDB.OnTransaction(m.t, database.WithRollback(nil))

				{ // tx block
					m.subscriptionViewRepo.On("Count", ctx, tx, mock.Anything).
						Return(int64(1), nil).Once()
					m.subscriptionNotificationTypeRepo.On("CreateBatch", ctx, tx, mock.Anything, mock.AnythingOfType("repository.OptionsFunc")).
						Return(int64(1), nil).Once()

					// fail here
					m.subscriptionViewRepo.On("GetByID", ctx, tx, "", mock.AnythingOfType("repository.OptionsFunc")).
						Return((*model.VSubscription)(nil), repository.ErrNotFound).Once()
				}
			},
			requireErr: func(t require.TestingT, err error, i ...interface{}) {
				require.ErrorIs(t, err, smerrors.ErrNotFound)
			},
		},
		{
			name: "successfully update subscription with only add notification types",
			req: &proto.SubscriptionUpdateRequest{
				TenantCustomerId:     tenantCustomerID,
				AddNotificationTypes: []string{"CONTACT_UPDATED"},
			},
			mocksF: func(m serviceMocks) {
				ntName := "contact_updated"
				m.notificationTypeLT.On("GetIdByName", ntName).Return(uuid.NewString()).Once()

				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, tenantCustomerID, mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.NewString())}, nil).Once()

				tx := m.subDB.OnTransaction(m.t, database.WithCommit(nil))

				{ // tx block
					m.subscriptionViewRepo.On("Count", ctx, tx, mock.Anything).
						Return(int64(1), nil).Once()
					m.subscriptionNotificationTypeRepo.On("CreateBatch", ctx, tx, mock.Anything, mock.AnythingOfType("repository.OptionsFunc")).
						Return(int64(1), nil).Once()
					m.subscriptionViewRepo.On("GetByID", ctx, tx, "", mock.AnythingOfType("repository.OptionsFunc")).
						Return(&model.VSubscription{Notifications: pq.StringArray{ntName}}, nil).Once()
				}
			},
			requireErr: require.NoError,
			expectedResp: &proto.SubscriptionUpdateResponse{
				Subscription: &proto.SubscriptionDetailsResponse{
					NotificationTypes: []string{"contact_updated"},
				},
			},
		},
		{
			name: "error while removing notification types",
			req: &proto.SubscriptionUpdateRequest{
				TenantCustomerId:     tenantCustomerID,
				RemNotificationTypes: []string{"CONTACT_UPDATED"},
			},
			mocksF: func(m serviceMocks) {
				ntName := "CONTACT_UPDATED"
				m.notificationTypeLT.On("GetIdByName", ntName).Return(uuid.NewString()).Once()

				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, tenantCustomerID, mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.NewString())}, nil).Once()

				tx := m.subDB.OnTransaction(m.t, database.WithRollback(nil))

				{ // tx block
					m.subscriptionViewRepo.On("Count", ctx, tx, mock.Anything).
						Return(int64(1), nil).Once()

					// fail here
					m.subscriptionNotificationTypeRepo.On("Delete", ctx, tx, &model.SubscriptionNotificationType{},
						mock.AnythingOfType("repository.OptionsFunc"), mock.AnythingOfType("repository.OptionsFunc")).
						Return(int64(0), errors.New("db error")).Once()
				}
			},
			requireErr: require.Error,
		},
		{
			name: "error while getting the number of notification types after removal",
			req: &proto.SubscriptionUpdateRequest{
				TenantCustomerId:     tenantCustomerID,
				RemNotificationTypes: []string{"CONTACT_UPDATED"},
			},
			mocksF: func(m serviceMocks) {
				ntName := "CONTACT_UPDATED"
				m.notificationTypeLT.On("GetIdByName", ntName).Return(uuid.NewString()).Once()

				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, tenantCustomerID, mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.NewString())}, nil).Once()

				tx := m.subDB.OnTransaction(m.t, database.WithRollback(nil))

				{ // tx block
					m.subscriptionViewRepo.On("Count", ctx, tx, mock.Anything).
						Return(int64(1), nil).Once()
					m.subscriptionNotificationTypeRepo.On("Delete", ctx, tx, &model.SubscriptionNotificationType{},
						mock.AnythingOfType("repository.OptionsFunc"), mock.AnythingOfType("repository.OptionsFunc")).
						Return(int64(1), nil).Once()

					// fail here
					m.subscriptionNotificationTypeRepo.On("Count", ctx, tx, mock.AnythingOfType("repository.OptionsFunc")).
						Return(int64(0), errors.New("db error")).Once()
				}
			},
			requireErr: require.Error,
		},
		{
			name: "error - getting no notification types after removal",
			req: &proto.SubscriptionUpdateRequest{
				TenantCustomerId:     tenantCustomerID,
				RemNotificationTypes: []string{"CONTACT_UPDATED"},
			},
			mocksF: func(m serviceMocks) {
				ntName := "CONTACT_UPDATED"
				m.notificationTypeLT.On("GetIdByName", ntName).Return(uuid.NewString()).Once()

				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, tenantCustomerID, mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.NewString())}, nil).Once()

				tx := m.subDB.OnTransaction(m.t, database.WithRollback(nil))

				{ // tx block, pass here
					m.subscriptionViewRepo.On("Count", ctx, tx, mock.Anything).
						Return(int64(1), nil).Once()
					m.subscriptionNotificationTypeRepo.On("Delete", ctx, tx, &model.SubscriptionNotificationType{},
						mock.AnythingOfType("repository.OptionsFunc"), mock.AnythingOfType("repository.OptionsFunc")).
						Return(int64(1), nil).Once()
					m.subscriptionNotificationTypeRepo.On("Count", ctx, tx, mock.AnythingOfType("repository.OptionsFunc")).
						Return(int64(0), nil).Once()
				}
			},
			requireErr: require.Error,
		},
		{
			name: "successfully update subscription with both notification types and description",
			req: &proto.SubscriptionUpdateRequest{
				TenantCustomerId:     tenantCustomerID,
				Description:          lo.ToPtr("test"),
				RemNotificationTypes: []string{"CONTACT_UPDATED"},
			},
			mocksF: func(m serviceMocks) {
				ntName := "CONTACT_UPDATED"
				m.notificationTypeLT.On("GetIdByName", ntName).Return(uuid.NewString()).Once()

				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, tenantCustomerID, mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.NewString())}, nil).Once()

				tx := m.subDB.OnTransaction(m.t, database.WithCommit(nil))

				{ // tx block, pass here
					m.subscriptionViewRepo.On("Count", ctx, tx, mock.Anything).
						Return(int64(1), nil).Once()
					m.subscriptionNotificationTypeRepo.On("Delete", ctx, tx, &model.SubscriptionNotificationType{},
						mock.AnythingOfType("repository.OptionsFunc"), mock.AnythingOfType("repository.OptionsFunc")).
						Return(int64(1), nil).Once()
					m.subscriptionNotificationTypeRepo.On("Count", ctx, tx, mock.AnythingOfType("repository.OptionsFunc")).
						Return(int64(1), nil).Once()
					m.subscriptionViewRepo.On("Update", ctx, tx, mock.Anything,
						mock.AnythingOfType("repository.OptionsFunc"), mock.AnythingOfType("repository.OptionsFunc")).
						Run(func(args mock.Arguments) {
							sub, ok := args.Get(2).(*model.VSubscription)
							require.True(t, ok)
							existingNT := "DOMAIN_CREATED"
							(*sub).Notifications = pq.StringArray{existingNT}
						}).
						Return(int64(1), nil).Once()
				}
			},
			requireErr: require.NoError,
			expectedResp: &proto.SubscriptionUpdateResponse{
				Subscription: &proto.SubscriptionDetailsResponse{
					Description:       lo.ToPtr("test"),
					NotificationTypes: []string{"DOMAIN_CREATED"},
				},
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

			resp, err := s.UpdateSubscription(ctx, tc.req)
			tc.requireErr(t, err)
			require.Equal(t, tc.expectedResp, resp)
		})
	}
}
