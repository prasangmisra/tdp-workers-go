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
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	smerrors "github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/errors"
	"github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/model"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"
	"gorm.io/gorm"
)

func (suite *TestSuite) TestIntegrationDeleteSubscriptionByID() {
	t := suite.T()
	t.Parallel()
	ctx := context.Background()
	anyProtoFromString := func(t *testing.T, value string) *anypb.Any {
		stringValue := structpb.NewStringValue(value)
		protoValue, err := anypb.New(stringValue)
		require.NoError(t, err)
		return protoValue
	}

	// Make an instance of a SubscriptionCreateRequest
	testCreateRequest := &subscription.SubscriptionCreateRequest{
		TenantCustomerId:  opensrsTenantCustomerID,
		NotificationTypes: []string{"contact.created", "contact.deleted", "contact.updated"},
		Description:       lo.ToPtr("test"),
		NotificationEmail: "resseller@example.com",
		Url:               "https://resseller.example.com",
		Tags:              []string{"tag1", "tag2"},
		Metadata:          map[string]*anypb.Any{"reseller": anyProtoFromString(t, "custom")},
	}

	// This subscription is only for the test case of a successful deletion
	subOpensrsToSucceed, err := suite.srvc.CreateSubscription(ctx, testCreateRequest)
	require.NoError(t, err)
	require.NotEmpty(t, subOpensrsToSucceed)

	testCreateRequest.Url = "https://resseller2.example.com"
	// This subscription should never be deleted successfully
	subOpensrsToFail, err := suite.srvc.CreateSubscription(ctx, testCreateRequest)
	require.NoError(t, err)
	require.NotEmpty(t, subOpensrsToFail)

	// already deleted subscription of type webhook
	subWebhookOpensrsDeleted := &model.Subscription{
		TenantID:          opensrsTenantID,
		NotificationEmail: "deleted@example.com",
		DeletedDate:       &gorm.DeletedAt{Time: time.Now(), Valid: true},
	}

	// subscriptions of type polling
	subPollOpensrs := &model.Subscription{
		TenantID:          opensrsTenantID,
		NotificationEmail: "poll@example.com",
	}

	subPollEnom := &model.Subscription{
		TenantID:          enomTenantID,
		NotificationEmail: "poll@example.com",
	}

	err = suite.srvc.subDB.WithTransaction(func(tx database.Database) error {
		_, err = suite.srvc.subscriptionRepo.CreateBatch(ctx, tx, &[]*model.Subscription{subPollOpensrs, subPollEnom, subWebhookOpensrsDeleted})
		if err != nil {
			return err
		}

		ch := &model.SubscriptionWebhookChannel{
			SubscriptionID: subWebhookOpensrsDeleted.ID,
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
				SubscriptionID: subPollOpensrs.ID,
				TypeID:         typeID,
			},
			{
				SubscriptionID: subWebhookOpensrsDeleted.ID,
				TypeID:         typeID,
			},
		}
		_, err = suite.srvc.subscriptionNotificationTypeRepo.CreateBatch(ctx, tx, &nTypes)
		return err
	})

	tests := []struct {
		name string
		req  *subscription.SubscriptionDeleteRequest

		requireError require.ErrorAssertionFunc
		expectedResp *subscription.SubscriptionDeleteResponse
	}{
		{
			name: "delete subscription fail - subscription with not existing ID",
			req: &subscription.SubscriptionDeleteRequest{Id: uuid.New().String(),
				TenantCustomerId: opensrsTenantCustomerID},
			requireError: func(t require.TestingT, err error, msgAndArgs ...interface{}) {
				expected := smerrors.ErrNotFound
				require.Truef(t, errors.Is(err, expected), "expected error %q, got %q", expected, err)
			},
		},
		{
			name: "delete subscription fail - subscription is not of type webhook",
			req: &subscription.SubscriptionDeleteRequest{Id: subPollOpensrs.ID,
				TenantCustomerId: opensrsTenantCustomerID},
			requireError: func(t require.TestingT, err error, msgAndArgs ...interface{}) {
				expected := smerrors.ErrNotFound
				require.ErrorIs(t, err, expected)
			},
		},
		{
			name: "delete subscription fail - subscription is wrong type and tenant",
			req: &subscription.SubscriptionDeleteRequest{Id: subPollEnom.ID,
				TenantCustomerId: opensrsTenantCustomerID},
			requireError: func(t require.TestingT, err error, msgAndArgs ...interface{}) {
				expected := smerrors.ErrNotFound
				require.ErrorIs(t, err, expected)
			},
		},
		{
			name: "delete subscription fail - the provided subscription ID belongs to the different tenant",
			req:  &subscription.SubscriptionDeleteRequest{Id: subOpensrsToFail.Subscription.Id, TenantCustomerId: enomTenantCustomerID},
			requireError: func(t require.TestingT, err error, msgAndArgs ...interface{}) {
				expected := smerrors.ErrNotFound
				require.Truef(t, errors.Is(err, expected), "expected error %q, got %q", expected, err)
			},
		},
		{
			name: "delete subscription success",
			req: &subscription.SubscriptionDeleteRequest{Id: subOpensrsToSucceed.Subscription.Id,
				TenantCustomerId: opensrsTenantCustomerID},
			requireError: require.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			_, err := suite.srvc.DeleteSubscriptionByID(context.Background(), tt.req)
			tt.requireError(t, err)

			// Make sure the subscription doesn't exist after calling the delete method
			_, err = suite.srvc.GetSubscriptionByID(context.Background(), &subscription.SubscriptionGetRequest{Id: tt.req.Id, TenantCustomerId: tt.req.TenantCustomerId})
			expected := smerrors.ErrNotFound
			require.Truef(t, errors.Is(err, expected), "expected error %q, got %q", expected, err)
		})
	}

}
