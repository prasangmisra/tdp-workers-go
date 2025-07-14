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
)

func TestPauseSubscription(t *testing.T) {
	t.Parallel()
	ctx := context.Background()

	tests := []struct {
		name   string
		req    *proto.SubscriptionPauseRequest
		mocksF func(m serviceMocks)

		expectedResp *proto.SubscriptionPauseResponse
		requireErr   require.ErrorAssertionFunc
	}{
		{
			name: "error on getting TenantID",
			req:  &proto.SubscriptionPauseRequest{},
			mocksF: func(m serviceMocks) {
				// fail here
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return((*model.VTenantCustomer)(nil), errors.New("db error")).Times(1)
			},
			requireErr: require.Error,
		},
		{
			name: "error from DB on getting paused status ID",
			req:  &proto.SubscriptionPauseRequest{},
			mocksF: func(m serviceMocks) {
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.New().String())}, nil).Times(1)

				// fail here
				m.subscriptionStatusLT.On("GetIdByName", model.SubscriptionStatusFromProto[proto.SubscriptionStatus_PAUSED]).
					Return("", nil).Times(1)
			},
			requireErr: require.Error,
		},
		{
			name: "subscription update failed",
			req:  &proto.SubscriptionPauseRequest{},
			mocksF: func(m serviceMocks) {
				tenantCustomerID := uuid.New().String()
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: &tenantCustomerID}, nil).Times(1)

				m.subscriptionStatusLT.On("GetIdByName", model.SubscriptionStatusFromProto[proto.SubscriptionStatus_PAUSED]).
					Return(uuid.New().String(), nil).Times(1)

				m.subscriptionViewRepo.On("Update", ctx, m.subDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc"),
					mock.AnythingOfType("repository.OptionsFunc"),
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(int64(0), errors.New("db error")).Times(1)
			},
			requireErr: require.Error,
		},
		{
			name: "subscription not found",
			req:  &proto.SubscriptionPauseRequest{},
			mocksF: func(m serviceMocks) {
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.New().String())}, nil).Times(1)

				m.subscriptionStatusLT.On("GetIdByName", model.SubscriptionStatusFromProto[proto.SubscriptionStatus_PAUSED]).
					Return(uuid.New().String(), nil).Times(1)

				m.subscriptionViewRepo.On("Update", ctx, m.subDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc"),
					mock.AnythingOfType("repository.OptionsFunc"),
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(int64(0), nil).Times(1)

				// no rows found
				m.subscriptionViewRepo.On("Count", ctx, m.subDB, mock.AnythingOfType("repository.OptionsFunc")).
					Return(int64(0), nil).Times(1)
			},
			requireErr: require.Error,
		},
		{
			name: "db error while getting count when no rows updated",
			req:  &proto.SubscriptionPauseRequest{},
			mocksF: func(m serviceMocks) {
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.New().String())}, nil).Times(1)

				m.subscriptionStatusLT.On("GetIdByName", model.SubscriptionStatusFromProto[proto.SubscriptionStatus_PAUSED]).
					Return(uuid.New().String(), nil).Times(1)

				m.subscriptionViewRepo.On("Update", ctx, m.subDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc"),
					mock.AnythingOfType("repository.OptionsFunc"),
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(int64(0), nil).Times(1)

				// fail here
				m.subscriptionViewRepo.On("Count", ctx, m.subDB, mock.AnythingOfType("repository.OptionsFunc")).
					Return(int64(0), errors.New("db error")).Times(1)
			},
			requireErr: require.Error,
		},
		{
			name: "subscription not in active or degraded state",
			req:  &proto.SubscriptionPauseRequest{},
			mocksF: func(m serviceMocks) {
				tenantCustomerID := uuid.New().String()
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: &tenantCustomerID}, nil).Times(1)

				m.subscriptionStatusLT.On("GetIdByName", model.SubscriptionStatusFromProto[proto.SubscriptionStatus_PAUSED]).
					Return(uuid.New().String(), nil).Times(1)

				m.subscriptionViewRepo.On("Update", ctx, m.subDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc"),
					mock.AnythingOfType("repository.OptionsFunc"),
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(int64(0), nil).Times(1)

				// subscription exists, but not in active or degraded state
				m.subscriptionViewRepo.On("Count", ctx, m.subDB, mock.AnythingOfType("repository.OptionsFunc")).
					Return(int64(1), nil).Once()
			},
			requireErr: require.Error,
		},
		{
			name: "subscription update successful",
			req:  &proto.SubscriptionPauseRequest{},
			mocksF: func(m serviceMocks) {
				tenantCustomerID := uuid.New().String()
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: &tenantCustomerID}, nil).Times(1)

				m.subscriptionStatusLT.On("GetIdByName", model.SubscriptionStatusFromProto[proto.SubscriptionStatus_PAUSED]).
					Return(uuid.New().String(), nil).Times(1)

				m.subscriptionViewRepo.On("Update", ctx, m.subDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc"),
					mock.AnythingOfType("repository.OptionsFunc"),
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(int64(1), nil).Once()
			},
			requireErr: require.NoError,
			expectedResp: &proto.SubscriptionPauseResponse{
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

			resp, err := s.PauseSubscription(ctx, tc.req)
			tc.requireErr(t, err)
			require.Equal(t, tc.expectedResp, resp)
		})
	}
}
