//go:build integration

package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/samber/lo"
	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	proto "github.com/tucowsinc/tdp-messages-go/message/subscription"
	smerrors "github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/errors"
	"github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/model"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"
	"gorm.io/gorm"
)

func (suite *TestSuite) TestCreateSubscriptionSuccess() {
	t := suite.T()
	t.Parallel()
	anyProtoFromString := func(t *testing.T, value string) *anypb.Any {
		stringValue := structpb.NewStringValue(value)
		protoValue, err := anypb.New(stringValue)
		require.NoError(t, err)
		return protoValue
	}
	now := time.Now().UTC()
	req := &subscription.SubscriptionCreateRequest{
		TenantCustomerId:  opensrsTenantCustomerID,
		NotificationTypes: []string{"contact.created", "contact.deleted", "contact.updated"},
		Description:       lo.ToPtr("test"),
		NotificationEmail: "resseller@example.com",
		Url:               "https://resseller.example.com",
		Tags:              []string{"tag1", "tag2"},
		Metadata:          map[string]*anypb.Any{"reseller": anyProtoFromString(t, "custom")},
	}
	resp, err := suite.srvc.CreateSubscription(context.Background(), req)
	require.NoError(t, err)
	require.NotEmpty(t, resp)

	{
		// verify response
		actual := resp.GetSubscription()
		expected := &subscription.SubscriptionDetailsResponse{
			// assign fields that are automatically set in DB
			Id:          actual.GetId(),
			CreatedDate: actual.GetCreatedDate(),

			NotificationTypes: req.NotificationTypes,
			NotificationEmail: req.NotificationEmail,
			Url:               req.Url,
			Tags:              req.Tags,
			Metadata:          req.Metadata,
			Status:            subscription.SubscriptionStatus_ACTIVE,
			Description:       req.Description,
		}

		require.Equal(t, expected, actual)
	}

	{ // verify other fields of inserted subscription
		sub, err := suite.srvc.subscriptionRepo.GetByID(context.Background(), suite.srvc.subDB, resp.Subscription.Id)
		require.NoError(t, err)
		require.NotEmpty(t, sub)

		require.Equal(t, resp.Subscription.Id, sub.ID)
		require.Equal(t, lo.ToPtr(opensrsTenantCustomerID), sub.TenantCustomerID)
		require.Equal(t, lo.ToPtr(suite.cfg.SubscriptionDB.Username), sub.CreatedBy)
		require.Equal(t, opensrsTenantID, sub.TenantID)
		require.Truef(t, sub.CreatedDate.UTC().After(now) && sub.CreatedDate.UTC().Before(time.Now().UTC()), "CreatedDate is invalid")
		require.Nil(t, sub.UpdatedDate)
		require.Nil(t, sub.UpdatedBy)
		require.Nil(t, sub.DeletedDate)
		require.Nil(t, sub.DeletedBy)
	}
	t.Logf("successfully created subscription: %+v\n", resp)
}

func (suite *TestSuite) TestCreateSubscriptionFail() {
	t := suite.T()
	t.Parallel()

	tests := []struct {
		name string
		req  *subscription.SubscriptionCreateRequest
	}{
		{
			name: "TenantCustomerId doesn't exist",
			req: &subscription.SubscriptionCreateRequest{
				TenantCustomerId: uuid.New().String(),
			},
		},
		{
			name: "unknown notification type provided",
			req: &subscription.SubscriptionCreateRequest{
				TenantCustomerId:  opensrsTenantCustomerID,
				NotificationTypes: []string{"askfjsaklfjs;f"},
				NotificationEmail: "resseller@example.com",
				Url:               "https://resseller.example.com",
			},
		},
		{
			name: "no NotificationTypes provided",
			req: &subscription.SubscriptionCreateRequest{
				TenantCustomerId:  opensrsTenantCustomerID,
				NotificationEmail: "resseller@example.com",
				Url:               "https://resseller.example.com",
			},
		},
		{
			name: "no NotificationEmail provided",
			req: &subscription.SubscriptionCreateRequest{
				TenantCustomerId:  opensrsTenantCustomerID,
				NotificationTypes: []string{"contact.created"},
				Url:               "https://resseller.example.com",
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			resp, err := suite.srvc.CreateSubscription(context.Background(), tt.req)
			require.Error(t, err)
			require.Nil(t, resp)
		})
	}
}

func (suite *TestSuite) TestGetSubscriptionByID() {
	t := suite.T()
	t.Parallel()
	ctx := context.Background()
	anyProtoFromString := func(t *testing.T, value string) *anypb.Any {
		stringValue := structpb.NewStringValue(value)
		protoValue, err := anypb.New(stringValue)
		require.NoError(t, err)
		return protoValue
	}
	subWebhookOpensrs := &subscription.SubscriptionCreateRequest{
		TenantCustomerId:  opensrsTenantCustomerID,
		NotificationTypes: []string{"contact.created", "contact.deleted", "contact.updated"},
		Description:       lo.ToPtr("test"),
		NotificationEmail: "resseller@example.com",
		Url:               "https://resseller.example.com",
		Tags:              []string{"tag1", "tag2"},
		Metadata:          map[string]*anypb.Any{"reseller": anyProtoFromString(t, "custom")},
	}
	createRespWebhookOpenSRS, err := suite.srvc.CreateSubscription(ctx, subWebhookOpensrs)
	require.NoError(t, err)
	require.NotEmpty(t, createRespWebhookOpenSRS)

	subPollEnom := &model.Subscription{
		TenantID:          enomTenantID,
		NotificationEmail: "poll@example.com",
	}

	subWebhookEnomDeleted := &model.Subscription{
		TenantID:          enomTenantID,
		NotificationEmail: "deleted@example.com",
		DeletedDate:       &gorm.DeletedAt{Time: time.Now(), Valid: true},
	}
	err = suite.srvc.subDB.WithTransaction(func(tx database.Database) error {
		_, err = suite.srvc.subscriptionRepo.CreateBatch(ctx, tx, &[]*model.Subscription{subPollEnom, subWebhookEnomDeleted})
		if err != nil {
			return err
		}

		ch := &model.SubscriptionWebhookChannel{
			SubscriptionID: subWebhookEnomDeleted.ID,
			WebhookURL:     "https://deleted.com",
		}
		_, err = suite.srvc.subscriptionWebhookChannelRepo.Create(ctx, tx, ch)
		if err != nil {
			return err
		}

		typeID := suite.srvc.notificationTypeLT.GetIdByName("domain.transfer")
		nTypes := []*model.SubscriptionNotificationType{
			{
				SubscriptionID: subPollEnom.ID,
				TypeID:         typeID,
			},
			{
				SubscriptionID: subWebhookEnomDeleted.ID,
				TypeID:         typeID,
			},
		}
		_, err = suite.srvc.subscriptionNotificationTypeRepo.CreateBatch(ctx, tx, &nTypes)
		return err
	})
	require.NoError(t, err)

	tests := []struct {
		name string
		req  *subscription.SubscriptionGetRequest

		requireError require.ErrorAssertionFunc
		expectedResp *subscription.SubscriptionDetailsResponse
	}{
		{
			name: "success - webhook subscription found",
			req:  &subscription.SubscriptionGetRequest{Id: createRespWebhookOpenSRS.Subscription.Id, TenantCustomerId: subWebhookOpensrs.TenantCustomerId},

			requireError: require.NoError,
			expectedResp: &subscription.SubscriptionDetailsResponse{
				Id:                createRespWebhookOpenSRS.Subscription.Id,
				NotificationTypes: subWebhookOpensrs.NotificationTypes,
				NotificationEmail: subWebhookOpensrs.NotificationEmail,
				Url:               subWebhookOpensrs.Url,
				Tags:              subWebhookOpensrs.Tags,
				Metadata:          subWebhookOpensrs.Metadata,
				Status:            subscription.SubscriptionStatus_ACTIVE,
				Description:       subWebhookOpensrs.Description,
			},
		},
		{
			name: "not found - not a webhook subscription",
			req:  &subscription.SubscriptionGetRequest{Id: subPollEnom.ID, TenantCustomerId: enomTenantCustomerID},

			requireError: func(t require.TestingT, err error, msgAndArgs ...interface{}) {
				expected := smerrors.ErrNotFound
				require.Truef(t, errors.Is(err, expected), "expected error %q, got %q", expected, err)
			},
		},
		{
			name: "not found - wrong tenantID",
			req:  &subscription.SubscriptionGetRequest{Id: createRespWebhookOpenSRS.Subscription.Id, TenantCustomerId: enomTenantCustomerID},

			requireError: func(t require.TestingT, err error, msgAndArgs ...interface{}) {
				expected := smerrors.ErrNotFound
				require.Truef(t, errors.Is(err, expected), "expected error %q, got %q", expected, err)
			},
		},
		{
			name: "not found - wrong id",
			req:  &subscription.SubscriptionGetRequest{Id: uuid.New().String(), TenantCustomerId: subWebhookOpensrs.TenantCustomerId},

			requireError: func(t require.TestingT, err error, msgAndArgs ...interface{}) {
				expected := smerrors.ErrNotFound
				require.Truef(t, errors.Is(err, expected), "expected error %q, got %q", expected, err)
			},
		},
		{
			name: "not found - deleted",
			req:  &subscription.SubscriptionGetRequest{Id: subWebhookEnomDeleted.ID, TenantCustomerId: enomTenantCustomerID},

			requireError: func(t require.TestingT, err error, msgAndArgs ...interface{}) {
				expected := smerrors.ErrNotFound
				require.Truef(t, errors.Is(err, expected), "expected error %q, got %q", expected, err)
			},
		},
		{
			name:         "error - not existing tenantID",
			req:          &subscription.SubscriptionGetRequest{Id: createRespWebhookOpenSRS.Subscription.Id, TenantCustomerId: uuid.New().String()},
			requireError: require.Error,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			resp, err := suite.srvc.GetSubscriptionByID(context.Background(), tt.req)
			tt.requireError(t, err)

			{ // verify response
				actual := resp.GetSubscription()

				if tt.expectedResp != nil {
					tt.expectedResp.CreatedDate = actual.GetCreatedDate()
				}
				require.Equal(t, tt.expectedResp, actual)
			}
		})
	}
}

// This test should not run in parallel with other tests since they may impact the result
func (suite *TestSuite) TestListSubscriptions() {
	time.Sleep(60 * time.Second)
	t := suite.T()
	ctx := context.Background()
	subOpenSRS := &subscription.SubscriptionCreateRequest{
		TenantCustomerId:  opensrsTenantCustomerID,
		NotificationTypes: []string{"contact.created"},
		NotificationEmail: "resseller@example.com",
		Url:               "https://resseller1.example.com",
	}
	sub1OpenSRS, err := suite.srvc.CreateSubscription(ctx, subOpenSRS)
	require.NoError(t, err)
	require.NotEmpty(t, sub1OpenSRS)
	subOpenSRS.Url = "https://resseller2.example.com"
	sub2OpenSRS, err := suite.srvc.CreateSubscription(ctx, subOpenSRS)
	require.NoError(t, err)
	require.NotEmpty(t, sub2OpenSRS)
	subOpenSRS.Url = "https://resseller3.example.com"
	subOpenSRS.Description = lo.ToPtr("111111111111111")
	sub3OpenSRS, err := suite.srvc.CreateSubscription(ctx, subOpenSRS)
	require.NoError(t, err)
	require.NotEmpty(t, sub3OpenSRS)

	openSRSWebhookSubscriptions := []*proto.SubscriptionDetailsResponse{
		sub1OpenSRS.GetSubscription(), sub2OpenSRS.GetSubscription(), sub3OpenSRS.GetSubscription(),
	}

	subPollOpenSRS := &model.Subscription{
		TenantID:          opensrsTenantID,
		NotificationEmail: "poll@example.com",
	}

	subOpenSRSDeleted := &model.Subscription{
		TenantID:          opensrsTenantID,
		NotificationEmail: "deleted@example.com",
		DeletedDate:       &gorm.DeletedAt{Time: time.Now(), Valid: true},
	}
	err = suite.srvc.subDB.WithTransaction(func(tx database.Database) error {
		_, err = suite.srvc.subscriptionRepo.CreateBatch(ctx, tx, &[]*model.Subscription{subOpenSRSDeleted, subPollOpenSRS})
		if err != nil {
			return err
		}

		ch := &model.SubscriptionWebhookChannel{
			SubscriptionID: subOpenSRSDeleted.ID,
			WebhookURL:     "https://deleted.com",
		}
		_, err = suite.srvc.subscriptionWebhookChannelRepo.Create(ctx, tx, ch)
		if err != nil {
			return err
		}

		typeID := suite.srvc.notificationTypeLT.GetIdByName("contact.created")
		nTypes := []*model.SubscriptionNotificationType{
			{
				SubscriptionID: subOpenSRSDeleted.ID,
				TypeID:         typeID,
			},
			{
				SubscriptionID: subPollOpenSRS.ID,
				TypeID:         typeID,
			},
		}
		_, err = suite.srvc.subscriptionNotificationTypeRepo.CreateBatch(ctx, tx, &nTypes)
		return err
	})
	require.NoError(t, err)

	tests := []struct {
		name string
		req  *subscription.SubscriptionListRequest

		requireError       require.ErrorAssertionFunc
		requireRes         require.ComparisonAssertionFunc
		expectedList       []*proto.SubscriptionDetailsResponse
		expectedTotalCount int
	}{
		{
			name: "success without pagination - reply should contain all created openSRS subscriptions except the deleted one",
			req:  &subscription.SubscriptionListRequest{TenantCustomerId: opensrsTenantCustomerID},

			requireError:       require.NoError,
			requireRes:         require.Contains,
			expectedList:       openSRSWebhookSubscriptions,
			expectedTotalCount: len(openSRSWebhookSubscriptions),
		},
		{
			name: "success with pagination",
			req: &subscription.SubscriptionListRequest{
				TenantCustomerId: opensrsTenantCustomerID,
				Pagination: &common.PaginationRequest{
					PageNumber: 1,
					PageSize:   1,
					SortBy:     "description",
				},
			},

			requireError:       require.NoError,
			requireRes:         require.Contains,
			expectedList:       []*proto.SubscriptionDetailsResponse{sub3OpenSRS.GetSubscription()},
			expectedTotalCount: len(openSRSWebhookSubscriptions),
		},
		{
			name: "different tenant - reply should not contain any openSRS subscriptions",
			req:  &subscription.SubscriptionListRequest{TenantCustomerId: enomTenantCustomerID},

			requireError: require.NoError,
			requireRes:   require.NotContains,
			expectedList: openSRSWebhookSubscriptions,
		},
		{
			name:         "error - not existing tenantID",
			req:          &subscription.SubscriptionListRequest{TenantCustomerId: uuid.New().String()},
			requireError: require.Error,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			resp, err := suite.srvc.ListSubscriptions(context.Background(), tt.req)
			tt.requireError(t, err)

			{ // verify response
				for _, s := range tt.expectedList {
					tt.requireRes(t, resp.GetSubscriptions(), s)
				}
				if p := tt.req.GetPagination(); p != nil {
					require.Len(t, resp.GetSubscriptions(), int(p.GetPageSize()))
				} else {
					require.Len(t, resp.GetSubscriptions(), int(resp.GetTotalCount()))
				}

				// Since other tests may create more subscriptions if run before, check total count with LessOrEqual
				require.LessOrEqual(t, tt.expectedTotalCount, int(resp.GetTotalCount()))

				// should never return deleted subscriptions
				require.NotContains(t, resp.GetSubscriptions(), subOpenSRSDeleted)
				// should never return not webhook subscriptions
				require.NotContains(t, resp.GetSubscriptions(), subPollOpenSRS)
			}
		})
	}
}
