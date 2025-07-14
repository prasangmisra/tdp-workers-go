package service

import (
	"context"
	"errors"
	"github.com/google/uuid"
	"github.com/samber/lo"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	proto "github.com/tucowsinc/tdp-messages-go/message/subscription"
	smerrors "github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/errors"
	"github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/model"
	"github.com/tucowsinc/tdp-shared-go/repository/v3"
	"testing"
)

func TestDeleteSubscriptionByID(t *testing.T) {
	t.Parallel()

	ctx := context.Background()

	tests := []struct {
		name   string
		req    *proto.SubscriptionDeleteRequest
		mocksF func(m serviceMocks)

		expectedResp *proto.SubscriptionDeleteResponse
		requireErr   require.ErrorAssertionFunc
	}{
		{
			name: "error from DB on deleting subscription - caused by not finding a tenantID",
			req:  &proto.SubscriptionDeleteRequest{},
			mocksF: func(m serviceMocks) {
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return((*model.VTenantCustomer)(nil), repository.ErrNotFound).Times(1)
			},
			requireErr: func(t require.TestingT, err error, msgAndArgs ...interface{}) {
				expected := smerrors.ErrInvalidTenantCustomerID
				require.ErrorIs(t, err, expected)

			},
		},
		{
			name: "subscription not found",
			req:  &proto.SubscriptionDeleteRequest{},
			mocksF: func(m serviceMocks) {
				// pass here
				tenantCustomerID := uuid.New().String()
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: &tenantCustomerID}, nil).Times(1)
				// fail here
				m.subscriptionViewRepo.On("Delete", ctx, m.subDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(int64(0), nil).Times(1)
			},
			requireErr: func(t require.TestingT, err error, msgAndArgs ...interface{}) {
				expected := smerrors.ErrNotFound
				require.ErrorIs(t, err, expected)
			},
		},
		{
			name: "error from DB on deleting subscription ",
			req:  &proto.SubscriptionDeleteRequest{},
			mocksF: func(m serviceMocks) {
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.NewString())}, nil).Once()

				m.subscriptionViewRepo.On("Delete", ctx, m.subDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(int64(0), errors.New("db error")).Once()
			},
			requireErr: require.Error,
		},
		{
			name: "success - with webhook subscription channel",
			req:  &proto.SubscriptionDeleteRequest{},
			mocksF: func(m serviceMocks) {
				//pass all
				tenantCustomerID := uuid.New().String()
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: &tenantCustomerID}, nil).Times(1)
				m.subscriptionViewRepo.On("Delete", ctx, m.subDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(int64(1), nil).Times(1)
			},
			requireErr:   require.NoError,
			expectedResp: &proto.SubscriptionDeleteResponse{},
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			s, m := newServiceMocks(t)
			if tc.mocksF != nil {
				tc.mocksF(m)
			}

			resp, err := s.DeleteSubscriptionByID(ctx, tc.req)
			tc.requireErr(t, err)
			require.Equal(t, tc.expectedResp, resp)
		})
	}
}
