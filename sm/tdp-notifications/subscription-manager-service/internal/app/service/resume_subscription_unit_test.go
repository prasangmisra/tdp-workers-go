package service

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"
	"github.com/samber/lo"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	proto "github.com/tucowsinc/tdp-messages-go/message/subscription"
	"github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/model"
	"github.com/tucowsinc/tdp-shared-go/repository/v3"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
)

func TestResumeSubscription(t *testing.T) {
	t.Parallel()
	ctx := context.Background()

	const webhookURL = "https://webhook.com"

	tests := []struct {
		name   string
		req    *proto.SubscriptionResumeRequest
		mocksF func(m serviceMocks)

		expectedResp *proto.SubscriptionResumeResponse
		requireErr   require.ErrorAssertionFunc
	}{
		{
			name: "error on getting TenantID",
			req:  &proto.SubscriptionResumeRequest{},
			mocksF: func(m serviceMocks) {
				// fail here
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return((*model.VTenantCustomer)(nil), errors.New("db error")).Times(1)
			},
			requireErr: require.Error,
		},
		{
			name: "error from DB on getting active status ID",
			req:  &proto.SubscriptionResumeRequest{},
			mocksF: func(m serviceMocks) {
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.New().String())}, nil).Times(1)

				// fail here
				m.subscriptionStatusLT.On("GetIdByName", model.SubscriptionStatus_Active).
					Return("", nil).Times(1)
			},
			requireErr: require.Error,
		},
		{
			name: "subscription update failed",
			req:  &proto.SubscriptionResumeRequest{},
			mocksF: func(m serviceMocks) {
				tenantCustomerID := uuid.New().String()
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: &tenantCustomerID}, nil).Times(1)

				m.subscriptionStatusLT.On("GetIdByName", model.SubscriptionStatus_Active).
					Return(uuid.New().String(), nil).Times(1)

				tx := m.subDB.OnTransaction(m.t, database.WithRollback(nil))

				{ // tx block, fail here
					m.subscriptionViewRepo.On("Update", ctx, tx, mock.Anything,
						mock.AnythingOfType("repository.OptionsFunc")).
						Return(int64(0), errors.New("db error")).Times(1)
				}
			},
			requireErr: require.Error,
		},
		{
			name: "subscription not found",
			req:  &proto.SubscriptionResumeRequest{},
			mocksF: func(m serviceMocks) {
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.New().String())}, nil).Times(1)

				m.subscriptionStatusLT.On("GetIdByName", model.SubscriptionStatus_Active).
					Return(uuid.New().String(), nil).Times(1)

				tx := m.subDB.OnTransaction(m.t, database.WithRollback(nil))

				{ // tx block
					m.subscriptionViewRepo.On("Update", ctx, tx, mock.Anything,
						mock.AnythingOfType("repository.OptionsFunc")).
						Return(int64(0), nil).Times(1)

					// fail here
					m.subscriptionViewRepo.On("GetByID", ctx, tx, mock.Anything, mock.AnythingOfType("repository.OptionsFunc")).
						Return((*model.VSubscription)(nil), repository.ErrNotFound).Times(1)
				}
			},
			requireErr: require.Error,
		},
		{
			name: "db error while getting subscription but update successful",
			req:  &proto.SubscriptionResumeRequest{},
			mocksF: func(m serviceMocks) {
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.New().String())}, nil).Times(1)

				m.subscriptionStatusLT.On("GetIdByName", model.SubscriptionStatus_Active).
					Return(uuid.New().String(), nil).Times(1)

				tx := m.subDB.OnTransaction(m.t, database.WithRollback(nil))

				{ // tx block
					// Assume update is successful based on `rows_affected=1`
					m.subscriptionViewRepo.On("Update", ctx, tx, mock.Anything,
						mock.AnythingOfType("repository.OptionsFunc")).
						Return(int64(1), nil).Times(1)

					// fail here
					m.subscriptionViewRepo.On("GetByID", ctx, tx, mock.Anything, mock.AnythingOfType("repository.OptionsFunc")).
						Return((*model.VSubscription)(nil), errors.New("db error")).Times(1)
				}
			},
			requireErr: require.Error,
		},
		{
			name: "db error while getting subscription but update unsuccessful",
			req:  &proto.SubscriptionResumeRequest{},
			mocksF: func(m serviceMocks) {
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.New().String())}, nil).Times(1)

				m.subscriptionStatusLT.On("GetIdByName", model.SubscriptionStatus_Active).
					Return(uuid.New().String(), nil).Times(1)

				tx := m.subDB.OnTransaction(m.t, database.WithRollback(nil))

				{ // tx block
					// Assume update is unsuccessful based on `rows_affected=0`
					m.subscriptionViewRepo.On("Update", ctx, tx, mock.Anything,
						mock.AnythingOfType("repository.OptionsFunc")).
						Return(int64(0), nil).Times(1)

					// fail here
					m.subscriptionViewRepo.On("GetByID", ctx, tx, mock.Anything, mock.AnythingOfType("repository.OptionsFunc")).
						Return((*model.VSubscription)(nil), errors.New("db error")).Times(1)
				}
			},
			requireErr: require.Error,
		},
		{
			name: "subscription not in paused state",
			req:  &proto.SubscriptionResumeRequest{},
			mocksF: func(m serviceMocks) {
				tenantCustomerID := uuid.New().String()
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: &tenantCustomerID}, nil).Times(1)

				m.subscriptionStatusLT.On("GetIdByName", model.SubscriptionStatus_Active).
					Return(uuid.New().String(), nil).Times(1)

				tx := m.subDB.OnTransaction(m.t, database.WithRollback(nil))
				{ // tx block
					m.subscriptionViewRepo.On("Update", ctx, tx, mock.Anything,
						mock.AnythingOfType("repository.OptionsFunc")).
						Return(int64(0), nil).Times(1)

					// set status to active to fail the status check
					m.subscriptionViewRepo.On("GetByID", ctx, tx, mock.Anything,
						mock.AnythingOfType("repository.OptionsFunc")).
						Return(&model.VSubscription{TenantID: tenantCustomerID, WebhookURL: lo.ToPtr(webhookURL), Type: lo.ToPtr(model.SubscriptionType_Webhook), Status: model.SubscriptionStatus_Active}, nil).Times(1)
				}
			},
			requireErr: require.Error,
		},
		{
			name: "subscription update failed",
			req:  &proto.SubscriptionResumeRequest{},
			mocksF: func(m serviceMocks) {
				tenantCustomerID := uuid.New().String()
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: &tenantCustomerID}, nil).Times(1)

				m.subscriptionStatusLT.On("GetIdByName", model.SubscriptionStatus_Active).
					Return(uuid.New().String(), nil).Times(1)

				tx := m.subDB.OnTransaction(m.t, database.WithRollback(nil))

				{ // rows_affected = 0, but subscription exists with valid status
					// covering an unexpected case
					m.subscriptionViewRepo.On("Update", ctx, tx, mock.Anything,
						mock.AnythingOfType("repository.OptionsFunc")).
						Return(int64(0), nil).Times(1)

					m.subscriptionViewRepo.On("GetByID", ctx, tx, mock.Anything,
						mock.AnythingOfType("repository.OptionsFunc")).
						Return(&model.VSubscription{TenantID: tenantCustomerID, WebhookURL: lo.ToPtr(webhookURL), Type: lo.ToPtr(model.SubscriptionType_Webhook), Status: model.SubscriptionStatus_Active}, nil).Times(1)
				}
			},
			requireErr: require.Error,
		},
		{
			name: "subscription update successful",
			req:  &proto.SubscriptionResumeRequest{},
			mocksF: func(m serviceMocks) {
				tenantCustomerID := uuid.New().String()
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: &tenantCustomerID}, nil).Times(1)

				m.subscriptionStatusLT.On("GetIdByName", model.SubscriptionStatus_Active).
					Return(uuid.New().String(), nil).Times(1)

				tx := m.subDB.OnTransaction(m.t, database.WithCommit(nil))

				{ // pass all here in tx
					m.subscriptionViewRepo.On("Update", ctx, tx, mock.Anything,
						mock.AnythingOfType("repository.OptionsFunc")).
						Return(int64(1), nil).Times(1)

					m.subscriptionViewRepo.On("GetByID", ctx, tx, mock.Anything,
						mock.AnythingOfType("repository.OptionsFunc")).
						Return(&model.VSubscription{TenantID: tenantCustomerID, Type: lo.ToPtr(model.SubscriptionType_Webhook), Status: model.SubscriptionStatus_Paused}, nil).Times(1)
				}
			},
			requireErr: require.NoError,
			expectedResp: &proto.SubscriptionResumeResponse{
				Subscription: &proto.SubscriptionDetailsResponse{
					Status: proto.SubscriptionStatus_PAUSED,
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

			resp, err := s.ResumeSubscription(ctx, tc.req)
			tc.requireErr(t, err)
			require.Equal(t, tc.expectedResp, resp)
		})
	}
}
