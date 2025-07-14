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
)

func createSubscriptionReq(t *testing.T, s *Service, tenantCustomerID string) *subscription.SubscriptionCreateRequest {
	t.Helper()
	subWebhook := &subscription.SubscriptionCreateRequest{
		TenantCustomerId:  tenantCustomerID,
		Url:               "https://resseller.example.com",
		NotificationTypes: []string{"contact.created"},

		Description:       lo.ToPtr("initial description"),
		NotificationEmail: "resseller@example.com",
		Tags:              []string{"tag1", "tag2"},
		Metadata:          map[string]*anypb.Any{"reseller": anyProtoFromString(t, "custom")},
	}
	return subWebhook
}

func updateReqGenerate(t *testing.T, id string) *subscription.SubscriptionUpdateRequest {
	t.Helper()
	return &subscription.SubscriptionUpdateRequest{
		Id:                   id,
		TenantCustomerId:     enomTenantCustomerID,
		Metadata:             map[string]*anypb.Any{"reseller": anyProtoFromString(t, "dynamic")},
		NotificationEmail:    "new@email.com",
		Description:          lo.ToPtr("updated description"),
		Tags:                 []string{"tag1", "tag2", "tag3"},
		AddNotificationTypes: []string{"contact.updated"},
		RemNotificationTypes: []string{"contact.created"},
	}
}

func (suite *TestSuite) TestUpdateSubscription() {
	t := suite.T()
	t.Parallel()
	ctx := context.Background()

	// subscription for failure cases
	subWebhookOpensrs := createSubscriptionReq(t, suite.srvc, opensrsTenantCustomerID)
	createRespWebhookOpenSRS, err := suite.srvc.CreateSubscription(ctx, subWebhookOpensrs)
	require.NoError(t, err)
	require.NotEmpty(t, createRespWebhookOpenSRS)

	// subscription for happy path
	subWebhookEnom := createSubscriptionReq(t, suite.srvc, enomTenantCustomerID)
	createRespWebhookEnom, err := suite.srvc.CreateSubscription(ctx, subWebhookEnom)
	require.NoError(t, err)
	require.NotEmpty(t, createRespWebhookEnom)

	baseUpdateReq := updateReqGenerate(t, createRespWebhookEnom.Subscription.Id)

	// subscription update request with no tags and metadata
	subWebhookEnom2 := createSubscriptionReq(t, suite.srvc, enomTenantCustomerID)
	createRespWebhookEnom2, err := suite.srvc.CreateSubscription(ctx, subWebhookEnom2)
	require.NoError(t, err)
	require.NotEmpty(t, createRespWebhookEnom2)

	reqWithoutTagsAndMeta := updateReqGenerate(t, createRespWebhookEnom2.Subscription.Id)
	reqWithoutTagsAndMeta.Tags = nil     // remove tags from request
	reqWithoutTagsAndMeta.Metadata = nil // remove metadata from request

	// non-webhook subscription update request
	subPollEnom := &model.Subscription{
		TenantID:          enomTenantID,
		NotificationEmail: "poll@example.com",
	}
	err = suite.srvc.subDB.WithTransaction(func(tx database.Database) error {
		_, err = suite.srvc.subscriptionRepo.Create(ctx, tx, subPollEnom)
		if err != nil {
			return err
		}

		typeID := suite.srvc.notificationTypeLT.GetIdByName("domain.transfer")
		nTypes := []*model.SubscriptionNotificationType{
			{
				SubscriptionID: subPollEnom.ID,
				TypeID:         typeID,
			},
		}
		_, err = suite.srvc.subscriptionNotificationTypeRepo.CreateBatch(ctx, tx, &nTypes)
		return err
	})
	require.NoError(t, err)

	// subscription update request with invalid notification type
	subWebhookEnom5 := createSubscriptionReq(t, suite.srvc, enomTenantCustomerID)
	createRespWebhookEnom5, err := suite.srvc.CreateSubscription(ctx, subWebhookEnom5)
	require.NoError(t, err)
	require.NotEmpty(t, createRespWebhookEnom5)

	reqWithBadNotiType := updateReqGenerate(t, createRespWebhookEnom5.Subscription.Id)
	reqWithBadNotiType.AddNotificationTypes = []string{"20"}

	// subscription update request with add notification type already present
	subEnomNotiTypePresence := createSubscriptionReq(t, suite.srvc, enomTenantCustomerID)
	createRespEnomNTPresence, err := suite.srvc.CreateSubscription(ctx, subEnomNotiTypePresence)
	require.NoError(t, err)
	require.NotEmpty(t, createRespEnomNTPresence)

	reqWithNotiTypePresence := updateReqGenerate(t, createRespEnomNTPresence.Subscription.Id)
	reqWithNotiTypePresence.AddNotificationTypes = []string{"contact.created", "contact.updated", "domain.renewed"}
	reqWithNotiTypePresence.RemNotificationTypes = []string{"contact.deleted", "domain.created", "domain.renewed"}

	// test cases
	tests := []struct {
		name string
		req  *subscription.SubscriptionUpdateRequest

		requireError require.ErrorAssertionFunc
		expectedResp *subscription.SubscriptionDetailsResponse
	}{
		{
			name: "TenantCustomerId doesn't exist",
			req: &subscription.SubscriptionUpdateRequest{
				Id:               createRespWebhookOpenSRS.Subscription.Id,
				TenantCustomerId: uuid.New().String(),
			},

			requireError: require.Error,
		},
		{
			name: "TenantCustomerId doesn't match with subscription",
			req: &subscription.SubscriptionUpdateRequest{
				Id:               createRespWebhookOpenSRS.Subscription.Id,
				TenantCustomerId: enomTenantCustomerID,
			},

			requireError: require.Error,
		},
		{
			name: "Subscription is not webhook type",
			req: &subscription.SubscriptionUpdateRequest{
				Id:               subPollEnom.ID,
				TenantCustomerId: enomTenantCustomerID,
			},
			requireError: require.Error,
		},
		{
			name: "subscription successfully updated",
			req:  baseUpdateReq,

			requireError: require.NoError,
			expectedResp: &subscription.SubscriptionDetailsResponse{
				Id:                baseUpdateReq.Id,
				NotificationEmail: baseUpdateReq.NotificationEmail,
				NotificationTypes: []string{"contact.updated"},
				Description:       baseUpdateReq.Description,
				Url:               subWebhookEnom.Url,
				Tags:              baseUpdateReq.Tags,
				Metadata:          baseUpdateReq.Metadata,
				Status:            subscription.SubscriptionStatus_ACTIVE,
			},
		},
		{
			name: "subscription update without providing tags and metadata",
			req:  reqWithoutTagsAndMeta,

			requireError: require.NoError,
			expectedResp: &subscription.SubscriptionDetailsResponse{
				Id:                reqWithoutTagsAndMeta.Id,
				NotificationEmail: reqWithoutTagsAndMeta.NotificationEmail,
				NotificationTypes: []string{"contact.updated"},
				Description:       reqWithoutTagsAndMeta.Description,
				Url:               subWebhookEnom2.Url,
				Tags:              subWebhookEnom2.Tags,     // should remain same
				Metadata:          subWebhookEnom2.Metadata, // should remain same
				Status:            subscription.SubscriptionStatus_ACTIVE,
			},
		},
		{
			name: "subscription update with pre-existing and non-existing notification type",
			req:  reqWithNotiTypePresence,

			requireError: require.NoError,
			expectedResp: &subscription.SubscriptionDetailsResponse{
				Id:                reqWithNotiTypePresence.Id,
				NotificationEmail: reqWithNotiTypePresence.NotificationEmail,
				NotificationTypes: []string{"contact.created", "contact.updated"},
				Description:       reqWithNotiTypePresence.Description,
				Url:               subEnomNotiTypePresence.Url,
				Tags:              reqWithNotiTypePresence.Tags,
				Metadata:          reqWithNotiTypePresence.Metadata,
				Status:            subscription.SubscriptionStatus_ACTIVE,
			},
		},
		{
			name: "error - removing all notification types is not allowed",
			req: &subscription.SubscriptionUpdateRequest{
				Id:                   createRespWebhookOpenSRS.Subscription.Id,
				TenantCustomerId:     opensrsTenantCustomerID,
				RemNotificationTypes: []string{"contact.created"},
			},

			requireError: require.Error,
		},
		{
			name: "successfully update - subscription with only remove notification types",
			req: &subscription.SubscriptionUpdateRequest{
				Id:                   createRespWebhookOpenSRS.Subscription.Id,
				TenantCustomerId:     opensrsTenantCustomerID,
				RemNotificationTypes: []string{"contact.deleted"},
			},

			requireError: require.NoError,
			expectedResp: &subscription.SubscriptionDetailsResponse{
				Id:                createRespWebhookOpenSRS.Subscription.Id,
				NotificationEmail: createRespWebhookOpenSRS.Subscription.NotificationEmail,
				Description:       createRespWebhookOpenSRS.Subscription.Description,
				Url:               createRespWebhookOpenSRS.Subscription.Url,
				Tags:              createRespWebhookOpenSRS.Subscription.Tags,
				Metadata:          createRespWebhookOpenSRS.Subscription.Metadata,
				Status:            subscription.SubscriptionStatus_ACTIVE,
				NotificationTypes: []string{"contact.created"},
			},
		},
		{
			name: "subscription update with invalid notification type",
			req:  reqWithBadNotiType,

			requireError: func(t require.TestingT, err error, msgAndArgs ...interface{}) {
				expected := smerrors.ErrInvalidNotificationType
				require.ErrorIs(t, err, expected, "expected error %q, got %q", expected, err)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			resp, err := suite.srvc.UpdateSubscription(context.Background(), tt.req)
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
