// Publishes a test webhook notification
// Inserts a row into the notification table representing a webhook notification.  This will kick off the enqueuer process

// To run this:
// 1. Edit the enqueuer/configs/dev.yaml so it has the correct settings
// 2. From the enqueuer/ folder, run the following command:
//
// 	go run ./testing-tools/create-test-webhook-notification/create_test_webhook_notification.go
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
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-notifications/enqueuer/internal/config"
	logging "github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/logger/zap"

	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
)

const configPath = "configs"
const subscription_type = "contact.created" // The type of notification that we want to create a subscription for

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

	// FIRSTLY, before we do anything else - let's look up some data from the database

	// Get a tenant/customer ID from the database
	// It looks like there is a bug in the test database where the two test subscriptions
	// that are created do NOT have a tenant_id or tenant_customer_id set.  So, we will hardcode them for now
	tenantId := uuid.NewString()
	tenantCustomerId := uuid.NewString()

	// Next, get the ID for the notification type that we want to create a subscription for
	tx := db.GetDB()
	var notification_type_contactcreated string
	sql := `SELECT tc_id_from_name('notification_type',?)`
	err = tx.Raw(sql, subscription_type).Scan(&notification_type_contactcreated).Error
	if err != nil {
		logger.Fatal("failed to get notification type ID", logging.Fields{"error": err})
		os.Exit(1)
	}

	// Generate some bogus data that can be serialized as a part of the subscription creation
	testdata := ryinterface.DomainInfoResponse{
		Name: "example.com",
	}
	serializedData, _ := json.Marshal(&testdata)

	test_subscription_description := "Test webhook subscription"

	// Okay, go ahead and create the subscription!

	// Create a new subscription
	var subscriptionId string
	sql = `INSERT INTO subscription(created_date, created_by, descr, tenant_id, tenant_customer_id, notification_email, metadata, tags) VALUES (?, ?, ?, ?, ?, ?, ?, ?) RETURNING id`
	// The RETURNING id will return the ID of the newly created subscription
	err = tx.Raw(sql, time.Now(), "tucows", test_subscription_description, tenantId, tenantCustomerId, "foo@bar.com", serializedData, "{}").Scan(&subscriptionId).Error
	if err != nil {
		logger.Fatal("failed to create subscription", logging.Fields{"error": err})
		os.Exit(1)
	}
	logger.Info("Created subscription with ID: " + subscriptionId + "; now need to create a webhook channel")
	// AFTER we create a subscription, we also need to create a specific webhook channel for it in the webhook_subscription table
	// Get the ID for the "webhook" channel type
	var webhookTypeId string
	sql = `SELECT tc_id_from_name('subscription_channel_type',?)`
	err = tx.Raw(sql, "webhook").Scan(&webhookTypeId).Error
	if err != nil {
		logger.Fatal("failed to get webhook channel type ID", logging.Fields{"error": err})
		os.Exit(1)
	}
	// Now create the subscription_webhook_channel entry
	sql = `INSERT INTO subscription_webhook_channel(created_date, created_by, id, type_id, subscription_id, webhook_url, signing_secret) VALUES (?,?, ?, ?, ?, ?, ?)`
	err = tx.Exec(sql,
		time.Now(),
		"tucows",
		uuid.NewString(),
		webhookTypeId,
		subscriptionId,
		"https://389b-99-248-214-46.ngrok-free.app/webhook",
		uuid.NewString()).Error
	if err != nil {
		logger.Fatal("failed to create subscription webhook channel", logging.Fields{"error": err})
		os.Exit(1)
	}
	logger.Info("Created webhook channel; now need to create a subscription notification type\n")

	// Finally, we need an entry in the subscription_notification_type table, associating the subscription with the "contact.created" notification type
	sql = `INSERT INTO subscription_notification_type(id, subscription_id, type_id) VALUES (?,?,?)`
	err = tx.Exec(sql, uuid.NewString(), subscriptionId, notification_type_contactcreated).Error
	if err != nil {
		logger.Fatal("failed to create subscription notification type", logging.Fields{"error": err})
		os.Exit(1)
	}
	logger.Info("Created subscription notification type.  Subscriber is ready! We can now create a notification that will trigger this newly created subscriber!\n")

	// Now, we need to create a notification that will trigger the subscriber
	var id string
	sql = `INSERT INTO notification(created_date, created_by, type_id,tenant_id, tenant_customer_id, payload) VALUES (?, ?, ?, ?, ?, ?) RETURNING id`
	err = tx.Raw(sql, time.Now(), "Gary", notification_type_contactcreated, tenantId, tenantCustomerId, serializedData).Scan(&id).Error
	if err != nil {
		logger.Fatal("failed to create notification", logging.Fields{"error": err})
		os.Exit(1)
	}
	logger.Info("Created notification with ID: " + id + ".  The enqueuer should pick this up!\n")
}
