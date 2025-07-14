//go:build integration

package service

//Integration tests for the UpdateNotificationStatus method in the service package
//This method is responsible for updating the status of a notification in the database
//In this test suite, we only consider "integration" between the service and a real database; we do not consider the integration service and the message bus.

//There are only two tests here; a happy "success" path that tests the update of a notification's status by going back to the actual database
//and a failure path where the notification to update did not exist in the database

//If you are running this test "manually" (i.e. out of VSCode), you will need to start the subdb.
//The easiest way to do that is to launch the subdb service from build/docker-compose.yaml ;
//You will need then to edit your dev.yaml file to that the hostname is `localhost`, is false and the port is 5434
//Finally, remove the "//go:build integration" from the top of this file

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/samber/lo"
	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-notifications/notification-manager-service/internal/app/config"
	nmerrors "github.com/tucowsinc/tdp-notifications/notification-manager-service/internal/app/errors"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestNotificationUpdateIntegrationTestSuite(t *testing.T) {
	suite.Run(t, new(NotificationUpdateIntegrationTestSuite))
}

type NotificationUpdateIntegrationTestSuite struct {
	//Fields that are common to all tests in the suite
	suite.Suite
	cfg         config.Config
	db          database.Database
	srvc        *Service
	testMessage datamanager.Notification
}

// Path to directory containing dev.yaml
const configPath = "../../../configs"

func (s *NotificationUpdateIntegrationTestSuite) SetupSuite() {
	// Suite setup.  Need to:
	// 1. Load the configuration
	// 2. Create a database connection
	// 3. Create a test message that we will be using for the tests

	// Load the configuration
	cfg, err := config.LoadConfiguration(configPath)
	s.cfg = cfg
	s.NoError(err)
	// Get a database connection
	subDB, err := database.New(cfg.SubscriptionDB.PostgresPoolConfig(), &logger.MockLogger{})
	s.NoError(err)
	s.db = subDB

	// Initialize the service with the database and configuration
	s.srvc, err = New(&logger.MockLogger{}, subDB)
	s.NoError(err)

	//Create a test message that we will be using for the tests.  Save it on the suite as a member for convenience
	s.testMessage = datamanager.Notification{
		Id:               uuid.New().String(),
		Status:           datamanager.DeliveryStatus_PUBLISHING,
		StatusReason:     "some_reason",
		Type:             "contact.created",
		TenantId:         uuid.New().String(),
		TenantCustomerId: lo.ToPtr(uuid.New().String()),
		WebhookUrl:       lo.ToPtr("http://localhost:8080/webhook"),
		SigningSecret:    lo.ToPtr(uuid.New().String()),
		CreatedDate:      timestamppb.Now(),
	}
}

// Test that updating a notification's status fails when the notification does not exist in the database
func (s *NotificationUpdateIntegrationTestSuite) TestNotificationStatusUpdateFailNotFound() {
	err := s.srvc.UpdateNotificationStatus(context.TODO(), &s.testMessage)
	s.Error(nmerrors.ErrNotFound, err)
}

// Test that updating a notification's status succeeds when the notification exists in the database
func (s *NotificationUpdateIntegrationTestSuite) TestNotificationStatusUpdateSuccess() {
	// In this test, we "properly" test the update of a notification's status
	// We first need to setup the database; specifically, we need to create a subscription (and related entities) and then a notification that triggers that subscription which in turn will create a v_notification entry
	// We take that v_notification's id, stick it in a Notification message, set its status to "published" and then pass it to the service
	// If the service works, the status of the v_notification in the database should be updated to "published"

	// Setup: create the subscription and notification
	// Get the ID of the created vnotification
	vnotificationID, err := CreateSubscriptionAndNotification(s.db, s.cfg, s)
	s.NoError(err, "failed to create subscription and notification")

	// Take our test Notification object and update its ID to the vnotification_id and its status to PUBLISHED
	s.testMessage.Id = vnotificationID
	s.testMessage.Status = datamanager.DeliveryStatus_PUBLISHED
	testStatusReason := "some_reason"
	s.testMessage.StatusReason = testStatusReason
	// Test our service!
	err = s.srvc.UpdateNotificationStatus(context.TODO(), &s.testMessage)
	s.Error(nmerrors.ErrNotFound, err)

	//Now verify that the status of the v_notification in the database has been updated to 'published'
	sql := `select status from v_notification where id = ?`
	var finalStatus string
	tx := s.db.GetDB()
	err = tx.Raw(sql, vnotificationID).Scan(&finalStatus).Error
	s.NoError(err, "failed to query for updated notification status")
	s.Equal("published", finalStatus)

	//Verify that the status_reason was updated
	//Now verify that the status of the v_notification in the database has been updated to 'published'
	sql = `select status_reason from v_notification where id = ?`
	var finalStatusReason string
	tx = s.db.GetDB()
	err = tx.Raw(sql, vnotificationID).Scan(&finalStatusReason).Error
	s.NoError(err, "failed to query for updated notification status")
	s.Require().NotNil(finalStatusReason)
	s.Equal(testStatusReason, finalStatusReason)
}

func CreateSubscriptionAndNotification(db database.Database, cfg config.Config, s *NotificationUpdateIntegrationTestSuite) (string, error) {
	// Helper method to create a subscription and a notification
	// Ugly SQL code here
	// FIRSTLY, before we do anything else - let's look up some data from the database

	// Get a tenant/customer ID from the database
	// It looks like there is a bug in the test database where the two test subscriptions
	// that are created do NOT have a tenant_id or tenant_customer_id set.  So, we will hardcode them for now
	tenantId := "26ac88c7-b774-4f56-938b-9f7378cb3eca"
	tenantCustomerId := "d50ff47e-2a80-4528-b455-6dc5d200ecbe"

	// Next, get the ID for the notification type (e.g. contact.created) that we want to create a subscription for
	tx := db.GetDB()
	var notificationTypeContactCreated string
	sql := `SELECT tc_id_from_name('notification_type',?)`
	subscriptionType := "contact.created"
	err := tx.Raw(sql, subscriptionType).Scan(&notificationTypeContactCreated).Error
	s.NoError(err, "failed to get notification type ID")

	// Generate some bogus data that can be serialized as a part of the subscription creation
	testdata := ryinterface.DomainInfoResponse{
		Name: "example.com",
	}
	serializedData, _ := json.Marshal(&testdata)

	// First, check if we have already created a test subscription
	sql = `SELECT * FROM subscription WHERE descr = 'Test subscription'`
	rows, err := tx.Raw(sql).Rows()
	s.NoError(err, "failed to query for existing subscription")
	if rows.Next() {
		fmt.Print("Subscription already exists; skipping creation\n")
	} else {
		// Okay, go ahead and create the subscription!

		// When we create the subscription, we want its status to be ACTIVE
		// Get the ID for the "active" status
		var activeStatusId string
		sql = `SELECT tc_id_from_name('subscription_status',?)`
		err = tx.Raw(sql, "active").Scan(&activeStatusId).Error
		s.NoError(err, "failed to get active status ID")

		// Generate a new ID for the subscription and then create it!
		subscriptionId := uuid.NewString()
		sql = `INSERT INTO subscription(created_date, created_by, id, descr, status_id, tenant_id, tenant_customer_id, notification_email, metadata, tags ) VALUES (?,?, ?, ?, ?, ?, ?, ?, ?, ?)`
		err = tx.Exec(sql, time.Now(), "tucows", subscriptionId, "Test subscription", activeStatusId, tenantId, tenantCustomerId, "foo@bar.com", serializedData, "{}").Error
		s.NoError(err, "failed to create subscription")

		// AFTER we create a subscription, we also need to create a specific webhook channel for it in the webhook_subscription table
		// Get the ID for the "webhook" channel type
		var webhookTypeId string
		sql = `SELECT tc_id_from_name('subscription_channel_type',?)`
		err = tx.Raw(sql, "webhook").Scan(&webhookTypeId).Error
		s.NoError(err, "failed to get webhook channel type ID")

		// Now create the subscription_webhook_channel entry
		sql = `INSERT INTO subscription_webhook_channel(created_date, created_by, id, type_id, subscription_id, webhook_url, signing_secret) VALUES (?,?, ?, ?, ?, ?, ?)`
		err = tx.Exec(sql,
			time.Now(),
			"tucows",
			uuid.NewString(),
			webhookTypeId,
			subscriptionId,
			"http://example.com",
			uuid.NewString()).Error
		s.NoError(err, "failed to create subscription webhook channel")

		// Finally, we need an entry in the subscription_notification_type table, associating the subscription with the "contact.created" notification type
		sql = `INSERT INTO subscription_notification_type(id, subscription_id, type_id) VALUES (?,?,?)`
		err = tx.Exec(sql, uuid.NewString(), subscriptionId, notificationTypeContactCreated).Error
		s.NoError(err, "failed to create subscription notification type")
	}

	// Now, we need to create a notification that will trigger the subscriber
	// Notice that we insert the row into the NOTIFICATION table.  This will run a trigger which will then create a row in the v_notification table
	id := uuid.NewString()
	sql = `INSERT INTO notification(created_date, created_by, id, type_id,tenant_id, tenant_customer_id, payload) VALUES (?, ?, ?, ?, ?, ?, ?)`
	err = tx.Exec(sql, time.Now(), "Gary", id, notificationTypeContactCreated, tenantId, tenantCustomerId, serializedData).Error
	s.NoError(err, "failed to create notification")

	// Get the ID of the v_notification that was created when the notification was created.
	// Pass this ID back to the test that called us because they will need it for verification
	sql = `SELECT id FROM v_notification WHERE notification_id = ? `
	var vNotificationId string
	err = tx.Raw(sql, id).Scan(&vNotificationId).Error
	return vNotificationId, err
}
