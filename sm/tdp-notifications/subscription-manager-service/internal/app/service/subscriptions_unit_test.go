package service

import (
	"context"
	"errors"
	"testing"

	"github.com/tucowsinc/tdp-messages-go/message/common"
	smerrors "github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/errors"

	"github.com/google/uuid"
	"github.com/lib/pq"
	"github.com/samber/lo"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	proto "github.com/tucowsinc/tdp-messages-go/message/subscription"
	"github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/model"
	"github.com/tucowsinc/tdp-shared-go/memoizelib"
	"github.com/tucowsinc/tdp-shared-go/repository/v3"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
	mocksrepo "github.com/tucowsinc/tdp-shared-go/repository/v3/mocks"
)

type serviceMocks struct {
	t                                *testing.T
	domainsDB, subDB                 *database.MockDatabase
	subscriptionRepo                 *mocksrepo.IRepository[*model.Subscription]
	subscriptionViewRepo             *mocksrepo.IRepository[*model.VSubscription]
	subscriptionWebhookChannelRepo   *mocksrepo.IRepository[*model.SubscriptionWebhookChannel]
	subscriptionNotificationTypeRepo *mocksrepo.IRepository[*model.SubscriptionNotificationType]
	tenantCustomerRepo               *mocksrepo.IRepository[*model.VTenantCustomer]
	notificationTypeLT               *mocksrepo.ILookupTable[*model.NotificationType]
	subscriptionStatusLT             *mocksrepo.ILookupTable[*model.SubscriptionStatus]
}

func newServiceMocks(t *testing.T) (s *Service, m serviceMocks) {
	t.Helper()

	m = serviceMocks{
		t:                                t,
		domainsDB:                        database.NewMockDatabase(t),
		subDB:                            database.NewMockDatabase(t),
		subscriptionRepo:                 mocksrepo.NewIRepository[*model.Subscription](t),
		subscriptionViewRepo:             mocksrepo.NewIRepository[*model.VSubscription](t),
		subscriptionWebhookChannelRepo:   mocksrepo.NewIRepository[*model.SubscriptionWebhookChannel](t),
		subscriptionNotificationTypeRepo: mocksrepo.NewIRepository[*model.SubscriptionNotificationType](t),
		tenantCustomerRepo:               mocksrepo.NewIRepository[*model.VTenantCustomer](t),
		notificationTypeLT:               mocksrepo.NewILookupTable[*model.NotificationType](t),
		subscriptionStatusLT:             mocksrepo.NewILookupTable[*model.SubscriptionStatus](t),
	}

	s = &Service{
		domainsDB:                        m.domainsDB,
		subDB:                            m.subDB,
		subscriptionRepo:                 m.subscriptionRepo,
		subscriptionViewRepo:             m.subscriptionViewRepo,
		subscriptionWebhookChannelRepo:   m.subscriptionWebhookChannelRepo,
		subscriptionNotificationTypeRepo: m.subscriptionNotificationTypeRepo,
		tenantCustomerRepo:               m.tenantCustomerRepo,
		notificationTypeLT:               m.notificationTypeLT,
		subscriptionStatusLT:             m.subscriptionStatusLT,
		tenantCustomerCache:              memoizelib.New[*model.VTenantCustomer](100, 100),
	}
	return
}

func TestCreateSubscription(t *testing.T) {
	t.Parallel()
	ctx := context.Background()

	tests := []struct {
		name   string
		req    *proto.SubscriptionCreateRequest
		mocksF func(m serviceMocks)

		expectedResp *proto.SubscriptionCreateResponse
		requireErr   require.ErrorAssertionFunc
	}{
		{
			name: "error on getting TenantID",
			req:  &proto.SubscriptionCreateRequest{},
			mocksF: func(m serviceMocks) {
				// fail here
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return((*model.VTenantCustomer)(nil), errors.New("db error")).Times(1)
			},
			requireErr: require.Error,
		},
		{
			name: "error on mapping notification types",
			req:  &proto.SubscriptionCreateRequest{NotificationTypes: []string{""}},
			mocksF: func(m serviceMocks) {
				// pass here
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.New().String())}, nil).Times(1)

				// fail here
				m.notificationTypeLT.On("GetIdByName", "").
					Return("").Times(1)
			},
			requireErr: require.Error,
		},
		{
			name: "error on creating subscription",
			req:  &proto.SubscriptionCreateRequest{},
			mocksF: func(m serviceMocks) {
				// pass here
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.New().String())}, nil).Times(1)

				tx := m.subDB.OnTransaction(m.t, database.WithRollback(nil))

				// fail here in tx
				m.subscriptionRepo.On("Create", ctx, tx, mock.Anything).
					Return(int64(0), errors.New("db error")).Times(1)

			},
			requireErr: require.Error,
		},
		{
			name: "error on creating webhook channel",
			req:  &proto.SubscriptionCreateRequest{},
			mocksF: func(m serviceMocks) {
				// pass here
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.New().String())}, nil).Times(1)

				tx := m.subDB.OnTransaction(m.t, database.WithRollback(nil))

				// pass here in tx
				m.subscriptionRepo.On("Create", ctx, tx, mock.Anything).
					Return(int64(1), nil).Times(1)

				// fail here in tx
				m.subscriptionWebhookChannelRepo.On("Create", ctx, tx, mock.Anything).
					Return(int64(0), errors.New("db error")).Times(1)

			},
			requireErr: require.Error,
		},
		{
			name: "error on creating Notification Types",
			req:  &proto.SubscriptionCreateRequest{NotificationTypes: []string{"asdf"}},
			mocksF: func(m serviceMocks) {
				{ // pass all here
					m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
						mock.AnythingOfType("repository.OptionsFunc")).
						Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.New().String())}, nil).Times(1)
					m.notificationTypeLT.On("GetIdByName", mock.Anything).
						Return("1").Times(1)
				}

				tx := m.subDB.OnTransaction(m.t, database.WithRollback(nil))

				{ // pass all here in tx
					m.subscriptionRepo.On("Create", ctx, tx, mock.Anything).
						Return(int64(1), nil).Times(1)
					m.subscriptionWebhookChannelRepo.On("Create", ctx, tx, mock.Anything).
						Return(int64(1), nil).Times(1)
				}

				// fail here in tx
				m.subscriptionNotificationTypeRepo.On("CreateBatch", ctx, tx, mock.Anything).
					Return(int64(0), errors.New("db error")).Times(1)

			},
			requireErr: require.Error,
		},
		{
			name: "error on retrieving created subscription",
			req:  &proto.SubscriptionCreateRequest{NotificationTypes: []string{"1"}},
			mocksF: func(m serviceMocks) {
				{ // pass all here
					m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
						mock.AnythingOfType("repository.OptionsFunc")).
						Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.New().String())}, nil).Times(1)
					m.notificationTypeLT.On("GetIdByName", mock.Anything).
						Return("1").Times(1)
				}

				tx := m.subDB.OnTransaction(m.t, database.WithRollback(nil))

				{ // pass all here in tx
					m.subscriptionRepo.On("Create", ctx, tx, mock.Anything).
						Return(int64(1), nil).Times(1)
					m.subscriptionWebhookChannelRepo.On("Create", ctx, tx, mock.Anything).
						Return(int64(1), nil).Times(1)
					m.subscriptionNotificationTypeRepo.On("CreateBatch", ctx, tx, mock.Anything).
						Return(int64(1), nil).Times(1)
				}

				// fail here in tx
				m.subscriptionViewRepo.On("GetByID", ctx, tx, mock.Anything).
					Return((*model.VSubscription)(nil), errors.New("db error")).Times(1)

			},
			requireErr: require.Error,
		},
		{
			name: "success",
			req:  &proto.SubscriptionCreateRequest{NotificationTypes: []string{"CONTACT_UPDATED"}},
			mocksF: func(m serviceMocks) {
				notifType := "CONTACT_UPDATED"

				{ // pass all here
					m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
						mock.AnythingOfType("repository.OptionsFunc")).
						Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.New().String())}, nil).Times(1)
					m.notificationTypeLT.On("GetIdByName", mock.Anything).
						Return(notifType).Times(1)
				}

				tx := m.subDB.OnTransaction(m.t, database.WithCommit(nil))

				{ // pass all here in tx
					m.subscriptionRepo.On("Create", ctx, tx, mock.Anything).
						Return(int64(1), nil).Times(1)
					m.subscriptionWebhookChannelRepo.On("Create", ctx, tx, mock.Anything).
						Return(int64(1), nil).Times(1)
					m.subscriptionNotificationTypeRepo.On("CreateBatch", ctx, tx, mock.Anything).
						Return(int64(1), nil).Times(1)
					m.subscriptionViewRepo.On("GetByID", ctx, tx, mock.Anything).
						Return(&model.VSubscription{Notifications: pq.StringArray{notifType}}, nil).Times(1)
				}

			},
			requireErr: require.NoError,
			expectedResp: &proto.SubscriptionCreateResponse{
				Subscription: &proto.SubscriptionDetailsResponse{
					NotificationTypes: []string{"CONTACT_UPDATED"}, //[]proto.NotificationType{proto.NotificationType_CONTACT_UPDATED},
				}},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			s, m := newServiceMocks(t)
			if tc.mocksF != nil {
				tc.mocksF(m)
			}

			resp, err := s.CreateSubscription(ctx, tc.req)
			tc.requireErr(t, err)
			require.Equal(t, tc.expectedResp, resp)
		})
	}
}

func TestGetSubscriptionByID(t *testing.T) {
	t.Parallel()

	ctx := context.Background()
	const webhookURL = "https://webhook.com"

	tests := []struct {
		name   string
		req    *proto.SubscriptionGetRequest
		mocksF func(m serviceMocks)

		expectedResp *proto.SubscriptionGetResponse
		requireErr   require.ErrorAssertionFunc
	}{
		{
			name: "error on getting TenantID",
			req:  &proto.SubscriptionGetRequest{},
			mocksF: func(m serviceMocks) {
				// fail here
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return((*model.VTenantCustomer)(nil), errors.New("db error")).Times(1)
			},
			requireErr: require.Error,
		},
		{
			name: "error from DB on getting subscription",
			req:  &proto.SubscriptionGetRequest{},
			mocksF: func(m serviceMocks) {
				// pass here
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.New().String())}, nil).Times(1)

				// fail here
				m.subscriptionViewRepo.On("GetByID", ctx, m.subDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return((*model.VSubscription)(nil), errors.New("db error")).Times(1)

			},
			requireErr: require.Error,
		},
		{
			name: "subscription not found",
			req:  &proto.SubscriptionGetRequest{},
			mocksF: func(m serviceMocks) {
				// pass here
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: lo.ToPtr(uuid.New().String())}, nil).Times(1)

				// fail here
				m.subscriptionViewRepo.On("GetByID", ctx, m.subDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return((*model.VSubscription)(nil), repository.ErrNotFound).Times(1)

			},
			requireErr: func(t require.TestingT, err error, msgAndArgs ...interface{}) {
				expected := smerrors.ErrNotFound
				require.Truef(t, errors.Is(err, expected), "expected error %v, got %v", expected, err)
			},
		},
		{
			name: "success - with webhook subscription channel",
			req:  &proto.SubscriptionGetRequest{},
			mocksF: func(m serviceMocks) {
				//pass all
				tenantCustomerID := uuid.New().String()
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: &tenantCustomerID}, nil).Times(1)
				m.subscriptionViewRepo.On("GetByID", ctx, m.subDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VSubscription{TenantID: tenantCustomerID, WebhookURL: lo.ToPtr(webhookURL), Type: lo.ToPtr(model.SubscriptionType_Webhook)}, nil).Times(1)
			},
			requireErr: require.NoError,
			expectedResp: &proto.SubscriptionGetResponse{
				Subscription: &proto.SubscriptionDetailsResponse{
					Url: webhookURL,
				}},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			s, m := newServiceMocks(t)
			if tc.mocksF != nil {
				tc.mocksF(m)
			}

			resp, err := s.GetSubscriptionByID(ctx, tc.req)
			tc.requireErr(t, err)
			require.Equal(t, tc.expectedResp, resp)
		})
	}
}

func TestListSubscriptions(t *testing.T) {
	t.Parallel()

	const webhookURL = "https://webhook.com"
	ctx := context.Background()

	tests := []struct {
		name   string
		req    *proto.SubscriptionListRequest
		mocksF func(m serviceMocks)

		expectedResp *proto.SubscriptionListResponse
		requireErr   require.ErrorAssertionFunc
	}{
		{
			name: "error on getting TenantID",
			req:  &proto.SubscriptionListRequest{},
			mocksF: func(m serviceMocks) {
				// fail here
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return((*model.VTenantCustomer)(nil), errors.New("db error")).Times(1)
			},
			requireErr: require.Error,
		},
		{
			name: "error from DB on getting count",
			req: &proto.SubscriptionListRequest{
				TenantCustomerId: uuid.New().String(),
				Pagination:       &common.PaginationRequest{PageSize: 1, PageNumber: 2},
			},
			mocksF: func(m serviceMocks) {
				//pass all
				tenantCustomerID := uuid.New().String()
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: &tenantCustomerID}, nil).Times(1)
				m.subscriptionViewRepo.On("Count", ctx, m.subDB, mock.Anything).
					Return(int64(0), errors.New("db error")).Times(1)
			},
			requireErr: require.Error,
		},
		{
			name: "error from DB on getting subscription",
			req:  &proto.SubscriptionListRequest{TenantCustomerId: uuid.New().String()},
			mocksF: func(m serviceMocks) {
				//pass all
				tenantCustomerID := uuid.New().String()
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: &tenantCustomerID}, nil).Times(1)
				m.subscriptionViewRepo.On("Find", ctx, m.subDB,
					mock.AnythingOfType("repository.OptionsFunc"),
				).Return(([]*model.VSubscription)(nil), errors.New("db error")).Times(1)
			},
			requireErr: require.Error,
		},
		{
			name: "success - without pagination",
			req:  &proto.SubscriptionListRequest{TenantCustomerId: uuid.New().String()},
			mocksF: func(m serviceMocks) {
				//pass all
				tenantCustomerID := uuid.New().String()
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: &tenantCustomerID}, nil).Times(1)
				m.subscriptionViewRepo.On("Find", ctx, m.subDB,
					mock.AnythingOfType("repository.OptionsFunc"),
				).Return(
					[]*model.VSubscription{
						{
							TenantID:   tenantCustomerID,
							WebhookURL: lo.ToPtr(webhookURL + "1"),
							Type:       lo.ToPtr(model.SubscriptionType_Webhook),
						},
						{
							TenantID:   tenantCustomerID,
							WebhookURL: lo.ToPtr(webhookURL + "2"),
							Type:       lo.ToPtr(model.SubscriptionType_Webhook),
						},
					},
					nil).Times(1)
			},
			requireErr: require.NoError,
			expectedResp: &proto.SubscriptionListResponse{
				Subscriptions: []*proto.SubscriptionDetailsResponse{
					{
						Url: webhookURL + "1",
					},
					{
						Url: webhookURL + "2",
					},
				},
				TotalCount: 2,
			},
		},
		{
			name: "success - with pagination when more than 0 found",
			req: &proto.SubscriptionListRequest{
				TenantCustomerId: uuid.New().String(),
				Pagination:       &common.PaginationRequest{PageSize: 1, PageNumber: 2},
			},
			mocksF: func(m serviceMocks) {
				//pass all
				tenantCustomerID := uuid.New().String()
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: &tenantCustomerID}, nil).Times(1)
				m.subscriptionViewRepo.On("Count", ctx, m.subDB, mock.Anything).
					Return(int64(2), nil).Times(1)
				m.subscriptionViewRepo.On("Find", ctx, m.subDB,
					mock.AnythingOfType("repository.OptionsFunc"),
					mock.AnythingOfType("repository.OptionsFunc"),
				).Return(
					[]*model.VSubscription{
						{
							TenantID:   tenantCustomerID,
							WebhookURL: lo.ToPtr(webhookURL),
							Type:       lo.ToPtr(model.SubscriptionType_Webhook),
						},
					},
					nil).Times(1)
			},
			requireErr: require.NoError,
			expectedResp: &proto.SubscriptionListResponse{
				Subscriptions: []*proto.SubscriptionDetailsResponse{
					{
						Url: webhookURL,
					},
				},
				TotalCount: 2,
			},
		},
		{
			name: "success - with pagination when 0 found",
			req: &proto.SubscriptionListRequest{
				TenantCustomerId: uuid.New().String(),
				Pagination:       &common.PaginationRequest{PageSize: 1, PageNumber: 2},
			},
			mocksF: func(m serviceMocks) {
				//pass all
				tenantCustomerID := uuid.New().String()
				m.tenantCustomerRepo.On("GetByID", ctx, m.domainsDB, mock.Anything,
					mock.AnythingOfType("repository.OptionsFunc")).
					Return(&model.VTenantCustomer{TenantID: &tenantCustomerID}, nil).Times(1)
				m.subscriptionViewRepo.On("Count", ctx, m.subDB, mock.Anything).
					Return(int64(0), nil).Times(1)
			},
			requireErr:   require.NoError,
			expectedResp: &proto.SubscriptionListResponse{TotalCount: 0},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			s, m := newServiceMocks(t)
			if tc.mocksF != nil {
				tc.mocksF(m)
			}

			resp, err := s.ListSubscriptions(ctx, tc.req)
			tc.requireErr(t, err)
			require.Equal(t, tc.expectedResp, resp)
		})
	}
}
