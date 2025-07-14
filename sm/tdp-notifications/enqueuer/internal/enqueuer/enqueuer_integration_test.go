//go:build integration

package enqueuer

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-notifications/enqueuer/internal/config"
	"github.com/tucowsinc/tdp-notifications/enqueuer/internal/database/model"
	"github.com/tucowsinc/tdp-notifications/enqueuer/internal/types"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/logger/zap"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
)

// These tests were copied over from the Enqueuer's home in the tdp-workers-go repository
// Notes:
// - these tests require the subscription and domains db running, making these integration tests
// - there were no unit tests in the original tdp-workers-go repository
// - the original tests were not complete (e.g. did not test row processing or message bus writing)
// - the original tests had little-to-no comments

// To run: simply run `make itest` from the enqueuer/ folder

// To debug/run these tests out of Visual Studio code:
// 1. Edit the `go.work` file in the root of the tdp-notifications/ directory and add the line
//     use enqueuer
// 2. Start the databases (from the parent tdp-notifications/ directory. run `make up`)
// 3. Comment out the line `//go:build integration` at the top of this file
// 4. Edit the .env file in the enqueuer/ folder
//	   - set DBPORT to 5434
//	   - set DBHOST to localhost
//  IMPORTANT: REMEMBER TO REVERT THESE CHANGES AFTER TESTING

func TestEnqueuerIntegrationTestSuite(t *testing.T) {
	suite.Run(t, new(EnqueuerIntegrationTestSuite))
}

type EnqueuerIntegrationTestSuite struct {
	suite.Suite
	db               database.Database
	mb               *mocks.MockMessageBus
	enqueuer         DbMessageEnqueuer[*model.VNotification]
	tenantId         string // Id used for testing
	tenantCustomerId string // Id used for testing
	logger           logger.ILogger
}

const configPath = "../../configs"

func (s *EnqueuerIntegrationTestSuite) SetupSuite() {
	config, err := config.LoadConfiguration(configPath)
	s.NoError(err, "Failed to read config from .env")

	zapConfig := zap.LoggerConfig{
		LogLevel:   config.Log.LogLevel,
		OutputSink: config.Log.OutputSink,
	}

	s.logger = zap.NewTdpLogger(zapConfig)

	db, err := database.New(config.SubscriptionDB.PostgresPoolConfig(), s.logger)
	s.NoError(err, types.LogMessages.DatabaseConnectionFailed)
	s.db = db

}

func (s *EnqueuerIntegrationTestSuite) SetupTest() {
	// Create a mock message bus
	s.mb = &mocks.MockMessageBus{}

	// Get a tenant/customer ID from the database
	// It looks like there is a bug in the test database where the two test subscriptions
	// that are created do NOT have a tenant_id or tenant_customer_id set.  So, we will hardcode them for now
	s.tenantId = "26ac88c7-b774-4f56-938b-9f7378cb3eca"
	s.tenantCustomerId = "d50ff47e-2a80-4528-b455-6dc5d200ecbe"

	// Configure the enqueuer by creating a new EnqueuerConfigBuilder
	// Specify:
	//  - the query to fetch notifications from the database
	//  - the field to update in the database after the message is enqueued
	//  - the queue that the notifications will be enqueued to
	enqueuerConfig, err := NewDbEnqueuerConfigBuilder[*model.VNotification]().
		WithRawSelect("SELECT vn.* FROM notification_delivery nd JOIN v_notification vn ON vn.id = nd.id WHERE vn.status = 'received' order by created_date desc LIMIT 100").
		WithUpdateFieldValueMap(map[string]interface{}{
			"status": "publishing"},
		).
		WithQueue("NotificationQueue").
		Build()
	s.NoError(err, "Failed to config enqueuer")

	// Create the enqueuer instance!
	enqueuer := DbMessageEnqueuer[*model.VNotification]{
		Db:     s.db.GetDB(),
		Bus:    s.mb,
		Config: enqueuerConfig,
		Log:    s.logger,
	}
	s.enqueuer = enqueuer
}

func (s *EnqueuerIntegrationTestSuite) TestGetRows() {
	// In this test, we will create a notification (and subscription)
	// and then run the enqueuer's getRows method to see if it finds the notification we created!

	// Create a notification
	messageId := uuid.NewString() // Generate a new UUID we will test against
	err := createTestNotification(s.db, messageId, s.tenantId, s.tenantCustomerId)
	s.NoError(err, "Failed to insert test notification message")

	ctx := context.Background()
	var rows []*model.VNotification
	// Get the rows from the database
	rows, err = s.enqueuer.getRows(ctx)
	s.NoError(err)
	s.NotNil(rows)
	s.Equal(messageId, rows[0].GetNotificationID()) //The first notification should be the one we created!
}

func (s *EnqueuerIntegrationTestSuite) TestUpdateRows() {
	// In this test, we will create a notification (and subscription)
	// and then run the enqueuer's updateRows method to test if it updates the rows appropriately

	ctx := context.Background()
	// Create a notification
	messageId := uuid.NewString()
	err := createTestNotification(s.db, messageId, s.tenantId, s.tenantCustomerId)
	s.NoError(err, "Failed to insert test notification message")

	// Firstly, get the rows to be updated (using the already tested getRows method)
	// The SELECT string was specified in the enqueuer configuration, which we did in the SetupTest method
	var rows []*model.VNotification
	rows, err = s.enqueuer.getRows(ctx)
	s.NoError(err)
	s.NotNil(rows)

	// Get a list of all the ids that were returned from the READ
	var ids []string
	for _, row := range rows {
		id := row.GetID()
		ids = append(ids, id)
	}
	// Iterate through each row and apply the enqueuer's update method
	// The UPDATE string was specified in the enqueuer configuration, which we did in the SetupTest method
	err = s.enqueuer.updateRows(ctx, ids)
	s.NoError(err)

	// Make sure the row's status was updated to "publishing"
	var verifyPublished string
	err = s.db.GetDB().Raw("SELECT status FROM v_notification WHERE notification_id = ?", messageId).Scan(&verifyPublished).Error
	s.NoError(err)
	s.Equal("publishing", verifyPublished)
}

func (s *EnqueuerIntegrationTestSuite) TestProcessRows() {
	// In this test, we will create a notification (and subscription)
	// and then run the enqueuer's processRows method to test if it updates row and then publishes them to RabbitMQ
	// Note that the processRows() method calls the updateRow() method, which we have already tested and will not bother retesting

	ctx := context.Background()
	// Create a notification
	messageId := uuid.NewString()
	err := createTestNotification(s.db, messageId, s.tenantId, s.tenantCustomerId)
	s.NoError(err, "Failed to insert test notification message")

	// Get the rows
	var rows []*model.VNotification
	rows, err = s.enqueuer.getRows(ctx)
	s.NoError(err)
	s.NotNil(rows)

	// Set up mock calls for bus
	s.mb.On("Send", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil, nil)
	err = s.enqueuer.processRows(ctx, rows, (*model.VNotification).ToWebhookProto)
	s.NoError(err) // If we got here, then the processRows hit the message bus and returned without error.  Success!
}

func (s *EnqueuerIntegrationTestSuite) TestEnqueuerDbMessages() {
	// Test the "kickoff" method - that is the method that runs all the other methods in the enqueuer
	// The "EnqueuerDbMessages(..)" method is the "master" function that calls the other methods.
	// This do-it-all method will scan for notifications, update their status, and then publish them to the message bus,
	// using the getRows/updateRows/processRows method we have already tested

	ctx := context.Background()
	// Create a test notification
	messageId := uuid.NewString()
	err := createTestNotification(s.db, messageId, s.tenantId, s.tenantCustomerId)
	s.NoError(err, "Failed to insert test notification message")

	s.mb.On("Send", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil, nil)
	s.enqueuer.EnqueuerDbMessages(ctx, (*model.VNotification).ToWebhookProto)

}

//=================================================================================================
// Helper methods
//=================================================================================================

// Helper method: creates a test subscription
func createTestSubscription(db database.Database, tenantId string, tenantCustomerId string) error {
	// Start the transaction
	tx := db.GetDB()

	// When we create the subscription, we want its status to be ACTIVE
	// Get the ID for the "active" status
	var activeStatusId string
	sql := `SELECT tc_id_from_name('subscription_status',?)`
	err := tx.Raw(sql, "active").Scan(&activeStatusId).Error
	if err != nil {
		return err
	}

	// Generate some bogus data that can be serialized as a part of the test subscription
	testdata := ryinterface.DomainInfoResponse{
		Name: "example.com",
	}
	serializedData, _ := json.Marshal(&testdata)

	// Generate a new ID for the subscription and create it!
	subscriptionId := uuid.NewString()
	sql = `INSERT INTO subscription(created_date, created_by, id, descr, status_id, tenant_id, tenant_customer_id, notification_email, metadata, tags ) VALUES (?,?, ?, ?, ?, ?, ?, ?, ?, ?)`
	err = tx.Exec(sql, time.Now(), "tucows", subscriptionId, "Test subscription", activeStatusId, tenantId, tenantCustomerId, "foo@bar.com", serializedData, "{}").Error
	if err != nil {
		//Could not create the subscription!
		return err
	}

	// When we create a subscription, we also need to create a specific webhook channel for it in the webhook_subscription table
	// Get the ID for the "webhook" channel type
	var webhookTypeId string
	sql = `SELECT tc_id_from_name('subscription_channel_type',?)`
	err = tx.Raw(sql, "webhook").Scan(&webhookTypeId).Error
	if err != nil {
		return err
	}
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
	if err != nil {
		//Could not create the subscription!
		return err
	}

	// Finally, we need an entry in the subscription_notification_type table, associating the subscription with the "contact.created" notification type
	var notification_type_contactcreated string
	sql = `SELECT tc_id_from_name('notification_type',?)`
	err = tx.Raw(sql, "contact.created").Scan(&notification_type_contactcreated).Error
	if err != nil {
		return err
	}

	sql = `INSERT INTO subscription_notification_type(id, subscription_id, type_id) VALUES (?,?,?)`
	err = tx.Exec(sql, uuid.NewString(), subscriptionId, notification_type_contactcreated).Error
	if err != nil {
		//Could not create the subscription!
		return err
	}

	return nil
}

// Helper method: creates a sbuscription and a notification
func createTestNotification(db database.Database, id string, tenantId string, tenantCustomerId string) (err error) {

	// First create a subscription
	err = createTestSubscription(db, tenantId, tenantCustomerId)
	if err != nil {
		return err
	}

	tx := db.GetDB()
	// Generate some bogus data that can be serialized as a part of the test subscription
	testdata := ryinterface.DomainInfoResponse{
		Name: "example.com",
	}
	serializedData, _ := json.Marshal(&testdata)

	var notification_type_contactcreated string
	sql := `SELECT tc_id_from_name('notification_type',?)`
	err = tx.Raw(sql, "contact.created").Scan(&notification_type_contactcreated).Error
	if err != nil {
		return
	}

	// Build an insert SQL statement from the parameters
	//sql = `INSERT INTO notification_delivery(id, notification_id,  created_date, channel_id, status_id, retries ) VALUES(?, ?, ?, ?, ?, ?)`
	//err = tx.Exec(sql, id, id, time.Now(), webhookTypeId, receivedStatusId, 0).Error
	sql = `INSERT INTO notification(created_date, created_by, id, type_id,tenant_id, tenant_customer_id, payload) VALUES (?, ?, ?, ?, ?, ?, ?)`
	err = tx.Exec(sql, time.Now(), "Gary", id, notification_type_contactcreated, tenantId, tenantCustomerId, serializedData).Error
	if err != nil {
		//Could not create the notification!
		return
	}
	return
}
