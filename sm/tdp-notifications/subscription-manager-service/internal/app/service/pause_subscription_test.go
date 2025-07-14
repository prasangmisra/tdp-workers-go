//go:build integration

package service

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/samber/lo"
	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	smerrors "github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/errors"
	"github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/model"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"
)

func (suite *TestSuite) TestPauseSubscription() {
	t := suite.T()
	t.Parallel()
	ctx := context.Background()
	anyProtoFromString := func(t *testing.T, value string) *anypb.Any {
		t.Helper()
		stringValue := structpb.NewStringValue(value)
		protoValue, err := anypb.New(stringValue)
		require.NoError(t, err)
		return protoValue
	}

	// subscription for failure cases
	subWebhookOpensrs := &subscription.SubscriptionCreateRequest{
		TenantCustomerId:  opensrsTenantCustomerID,
		NotificationTypes: []string{"contact.updated"},
		Description:       lo.ToPtr("test"),
		NotificationEmail: "resseller@example.com",
		Url:               "https://resseller.example.com",
		Tags:              []string{"tag1", "tag2"},
		Metadata:          map[string]*anypb.Any{"reseller": anyProtoFromString(t, "custom")},
	}
	createRespWebhookOpenSRS, err := suite.srvc.CreateSubscription(ctx, subWebhookOpensrs)
	require.NoError(t, err)
	require.NotEmpty(t, createRespWebhookOpenSRS)

	// subscription for happy path
	subWebhookEnom := &subscription.SubscriptionCreateRequest{
		TenantCustomerId:  enomTenantCustomerID,
		NotificationTypes: []string{"contact.updated"},
		Description:       lo.ToPtr("test enom"),
		NotificationEmail: "resseller@example.com",
		Url:               "https://resseller.example.com",
		Tags:              []string{"tag1", "tag2"},
		Metadata:          map[string]*anypb.Any{"reseller": anyProtoFromString(t, "custom")},
	}
	createRespWebhookEnom, err := suite.srvc.CreateSubscription(ctx, subWebhookEnom)
	require.NoError(t, err)
	require.NotEmpty(t, createRespWebhookEnom)

	// subscription already paused
	subWebhookEnomPaused := &model.Subscription{
		TenantID:          enomTenantID,
		NotificationEmail: "paused@example.com",
	}

	// subscriptions of type polling
	subPollEnom := &model.Subscription{
		TenantID:          enomTenantID,
		NotificationEmail: "poll@example.com",
	}
	subPollOpenSRS := &model.Subscription{
		TenantID:          opensrsTenantID,
		NotificationEmail: "poll@example.com",
	}

	err = suite.srvc.subDB.WithTransaction(func(tx database.Database) error {
		_, err := suite.srvc.subscriptionRepo.CreateBatch(ctx, tx, &[]*model.Subscription{subWebhookEnomPaused, subPollEnom, subPollOpenSRS})
		if err != nil {
			return err
		}

		ch := &model.SubscriptionWebhookChannel{
			SubscriptionID: subWebhookEnomPaused.ID,
			WebhookURL:     "https://paused.com",
		}
		_, err = suite.srvc.subscriptionWebhookChannelRepo.Create(ctx, tx, ch)
		if err != nil {
			return err
		}

		typeID := suite.srvc.notificationTypeLT.GetIdByName("contact.updated")
		nTypes := []*model.SubscriptionNotificationType{
			{
				SubscriptionID: subWebhookEnomPaused.ID,
				TypeID:         typeID,
			},
			{
				SubscriptionID: subPollEnom.ID,
				TypeID:         typeID,
			},
			{
				SubscriptionID: subPollOpenSRS.ID,
				TypeID:         typeID,
			},
		}
		_, err = suite.srvc.subscriptionNotificationTypeRepo.CreateBatch(ctx, tx, &nTypes)
		if err != nil {
			return err
		}

		_, err = suite.srvc.subscriptionRepo.Update(ctx, tx, &model.Subscription{
			ID:       subWebhookEnomPaused.ID,
			StatusID: suite.srvc.subscriptionStatusLT.GetIdByName("paused"),
		})
		return err
	})

	tests := []struct {
		name string
		req  *subscription.SubscriptionPauseRequest

		requireError require.ErrorAssertionFunc
		expectedResp *subscription.SubscriptionDetailsResponse
	}{
		{
			name: "TenantCustomerId doesn't exist",
			req: &subscription.SubscriptionPauseRequest{
				Id:               createRespWebhookOpenSRS.Subscription.Id,
				TenantCustomerId: uuid.New().String(),
			},

			requireError: require.Error,
		},
		{
			name: "subscription belongs to different tenant",
			req: &subscription.SubscriptionPauseRequest{
				Id:               createRespWebhookOpenSRS.Subscription.Id,
				TenantCustomerId: enomTenantCustomerID,
			},
			requireError: func(t require.TestingT, err error, msgAndArgs ...interface{}) {
				expected := smerrors.ErrNotFound
				require.ErrorIs(t, err, expected, "expected error %q, got %q", expected, err)
			},
		},
		{
			name: "subscription not found",
			req: &subscription.SubscriptionPauseRequest{
				Id:               uuid.New().String(),
				TenantCustomerId: opensrsTenantCustomerID,
			},

			requireError: func(t require.TestingT, err error, msgAndArgs ...interface{}) {
				expected := smerrors.ErrNotFound
				require.ErrorIs(t, err, expected, "expected error %q, got %q", expected, err)
			},
		},
		{
			name: "subscription already paused",
			req: &subscription.SubscriptionPauseRequest{
				Id:               subWebhookEnomPaused.ID,
				TenantCustomerId: enomTenantCustomerID,
			},
			requireError: func(t require.TestingT, err error, msgAndArgs ...interface{}) {
				expected := smerrors.ErrStatusCannotBePaused
				require.ErrorIs(t, err, expected, "expected error %q, got %q", expected, err)
			},
		},
		{
			name: "subscription successfully paused",
			req: &subscription.SubscriptionPauseRequest{
				Id:               createRespWebhookEnom.Subscription.Id,
				TenantCustomerId: enomTenantCustomerID,
			},

			requireError: require.NoError,
			expectedResp: &subscription.SubscriptionDetailsResponse{
				Id:                createRespWebhookEnom.Subscription.Id,
				NotificationEmail: subWebhookEnom.NotificationEmail,
				NotificationTypes: subWebhookEnom.NotificationTypes,
				Description:       subWebhookEnom.Description,
				Url:               subWebhookEnom.Url,
				Tags:              subWebhookEnom.Tags,
				Metadata:          subWebhookEnom.Metadata,
				Status:            subscription.SubscriptionStatus_PAUSED,
			},
		},
		{
			name: "subscription (enom) not a webhook type",
			req: &subscription.SubscriptionPauseRequest{
				Id:               subPollEnom.ID,
				TenantCustomerId: enomTenantCustomerID,
			},
			requireError: func(t require.TestingT, err error, msgAndArgs ...interface{}) {
				expected := smerrors.ErrNotFound
				require.ErrorIs(t, err, expected, "expected error %q, got %q", expected, err)
			},
		},
		{
			name: "subscription (opensrs) not a webhook type",
			req: &subscription.SubscriptionPauseRequest{
				Id:               subPollOpenSRS.ID,
				TenantCustomerId: opensrsTenantCustomerID,
			},
			requireError: func(t require.TestingT, err error, msgAndArgs ...interface{}) {
				expected := smerrors.ErrNotFound
				require.ErrorIs(t, err, expected, "expected error %q, got %q", expected, err)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			resp, err := suite.srvc.PauseSubscription(context.Background(), tt.req)
			tt.requireError(t, err)

			{ // verify response
				actual := resp.GetSubscription()

				if tt.expectedResp != nil {
					tt.expectedResp.CreatedDate = actual.CreatedDate
				}

				require.Equal(t, tt.expectedResp, actual)
			}
		})
	}
}
