// Publishes a test emaul notification
// Inserts a row into the notification table representing a webhook notification.  This will kick off the enqueuer process

// To run this:
// 1. Edit the enqueuer/configs/dev.yaml so it has the correct settings
// 2. From the enqueuer/ folder, run the following command:
//
// 	go run ./testing-tools/create-test-email-notification/create_test_email_notification.go
//
// This will create a new subscription in the database, and then create a notification that will trigger said subscription.
// You can then run the Enqueuer process, which will pick it up!

package main

import (
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/google/uuid"
	"github.com/samber/lo"
	"github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-notifications/enqueuer/internal/config"
	"google.golang.org/protobuf/types/known/structpb"

	logging "github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/logger/zap"

	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
)

const configPath = "configs"
const subscriptionType = "account.created" // The type of notification that we want to create a subscription for

func main() {
	config, err := config.LoadConfiguration(configPath)
	if err != nil {
		fmt.Print("failed to load tdp-notifications enqueuer configuration", logging.Fields{"error": err})
		os.Exit(1)
	}

	zapConfig := zap.LoggerConfig{
		LogLevel:   config.Log.LogLevel,
		OutputSink: config.Log.OutputSink,
	}
	logger := zap.NewTdpLogger(zapConfig)
	db, err := database.New(config.SubscriptionDB.PostgresPoolConfig(), logger)
	if err != nil {
		logger.Fatal("failed to create database connection", logging.Fields{"error": err})
	}

	// Firstly, create a tenant ID.
	tenantId := uuid.NewString()
	tenantCustomerId := uuid.NewString()

	// Next, get the ID for the notification type (e.g. account_created) that we want to create a subscription for
	tx := db.GetDB()
	var notificationTypeAccountCreated string
	sql := `SELECT tc_id_from_name('notification_type',?)`
	err = tx.Raw(sql, subscriptionType).Scan(&notificationTypeAccountCreated).Error
	if err != nil {
		logger.Fatal("failed to get notification type ID", logging.Fields{"error": err})
		os.Exit(1)
	}

	// Okay, go ahead and create the subscription!
	testSubscriptionDescription := "Test subscription for tenant " + tenantId + " for testing purposes"

	// Create a new subscription
	var subscriptionId string
	sql = `INSERT INTO subscription(created_date, created_by, descr, tenant_id, tenant_customer_id, notification_email, tags) VALUES (?, ?, ?, ?, ?, ?, ?) RETURNING id`
	// The RETURNING id will return the ID of the newly created subscription
	err = tx.Raw(sql, time.Now(), "tucows", testSubscriptionDescription, tenantId, tenantCustomerId, "foo@bar.com", "{}").Scan(&subscriptionId).Error
	if err != nil {
		logger.Fatal("failed to create subscription", logging.Fields{"error": err})
		os.Exit(1)
	}
	logger.Info("Created subscription with ID: " + subscriptionId + "; now need to create an email channel")

	// AFTER we create a subscription, we also need to create a specific email channel for it in the subscription_email_channel table
	// Get the ID for the "webhook" channel type
	var emailTypeId string
	sql = `SELECT tc_id_from_name('subscription_channel_type',?)`
	err = tx.Raw(sql, "email").Scan(&emailTypeId).Error
	if err != nil {
		logger.Fatal("failed to get webhook channel type ID", logging.Fields{"error": err})
		os.Exit(1)
	}

	// Now create the subscription_email_channel entry
	sql = `INSERT INTO subscription_email_channel(created_date, created_by, id, type_id, subscription_id) VALUES (?,?, ?, ?, ?)`
	err = tx.Exec(sql,
		time.Now(),
		"tucows",
		uuid.NewString(),
		emailTypeId,
		subscriptionId).Error
	if err != nil {
		logger.Fatal("failed to create subscription email channel", logging.Fields{"error": err})
		os.Exit(1)
	}
	logger.Info("Created email channel; now need to create a subscription notification type\n")

	// Now we need an entry in the subscription_notification_type table, associating the subscription with the "contact.created" notification type
	sql = `INSERT INTO subscription_notification_type(id, subscription_id, type_id) VALUES (?,?,?)`
	err = tx.Exec(sql, uuid.NewString(), subscriptionId, notificationTypeAccountCreated).Error
	if err != nil {
		logger.Fatal("failed to create subscription notification type", logging.Fields{"error": err})
		os.Exit(1)
	}

	// We're going to re-use the existing sample templates that are already in the database to save some time
	logger.Info("Created subscription notification type.  Subscriber is ready! We can now create a notification that will trigger this newly created subscriber!\n")

	//=============================================
	// Sample email
	//============================================
	// Need to create the payload for an email notification
	// The payload needs to be the seralized JSON of the EmailNotification object
	var toAddresses = []*common.Address{{
		Email: "gng01@tucowsinc.com",
		Name:  lo.ToPtr("Gary The Gary"),
	}}

	var fromAddress = common.Address{
		Email: "asdf@asdf.cd",
		Name:  lo.ToPtr("The Big Boss Man"),
	}
	envelope := common.EmailEnvelope{
		Subject:     "You're Promoted!",
		ToAddress:   toAddresses,
		FromAddress: &fromAddress,
	}

	template_data := map[string]any{
		"first_name":     "Gary",
		"last_name":      "Ng",
		"current_date":   time.Now().Format(time.RFC3339),
		"account_id":     "1234567890",
		"account_name":   "Test Account",
		"account_status": "active",
	}

	structValue, _ := structpb.NewStruct(template_data)

	emailNotification := common.EmailNotification{
		Envelope: &envelope,
		Data:     structValue,
	}

	serializedData, _ := json.Marshal(&emailNotification)

	// Now, we need to create a notification that will trigger the subscriber
	var id string
	sql = `INSERT INTO notification(created_date, created_by, type_id,tenant_id, tenant_customer_id, payload) VALUES (?, ?, ?, ?, ?, ?) RETURNING id`
	err = tx.Raw(sql, time.Now(), "Gary", notificationTypeAccountCreated, tenantId, tenantCustomerId, serializedData).Scan(&id).Error
	if err != nil {
		logger.Fatal("failed to create notification", logging.Fields{"error": err})
		os.Exit(1)
	}
	logger.Info("Created notification with ID: " + id + ".  The enqueuer should pick this up!\n")
}
