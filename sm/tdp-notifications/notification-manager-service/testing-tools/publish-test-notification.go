// Publishes a test "final" Notification message to the message bus.
// Queue name is taken from the config file (configs/dev.yaml)
// Note that this code will also create the queue if it doesn't exist.

// If the NotificationManager service is running, it will detect the message and attempt do its thing (i.e update the status of correspodning notification in the database)
// Note that the message this test creates uses a generated UUID for the ID field. This message will get picked up by the NotificationManager service BUT
// the ID will not match any existing notification in the database, so the service will return a "ErrNotFound" error.
// To properly test this, you should replace the ID field with an actual notification ID from the database.  See comments below.

package main

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"github.com/samber/lo"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/logging"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"github.com/tucowsinc/tdp-notifications/notification-manager-service/internal/app/config"
	"github.com/tucowsinc/tdp-shared-go/logger/zap"
	"google.golang.org/protobuf/types/known/timestamppb"
)

const configPath = "configs"
const (
	SERVICE_NAME = "notification_manager"
)

func main() {

	cfg, err := config.LoadConfiguration(configPath)
	logger := zap.NewTdpLogger(cfg.Log) // Log config is loaded by default values anyway
	if err != nil {
		logger.Fatal("failed to load tdp-notifications notification-manager-service configuration", logging.Fields{"error": err})
	}

	logger.Info("configuration successfully loaded, starting tdp-notifications notification-manager-service...")

	//Get a connection to the bus
	opts, err := messagebus.NewRabbitMQOptionsBuilder().
		WithExchange(cfg.RMQ.Exchange).
		WithQType(cfg.RMQ.QueueType).
		Build()
	if err != nil {
		logger.Fatal("failed to build message bus options", logging.Fields{"error": err})
	}
	mbOpts := messagebus.MessageBusOptions{
		CertFile:   cfg.RMQ.CertFile,
		KeyFile:    cfg.RMQ.KeyFile,
		CACertFile: cfg.RMQ.CAFile,
		SkipVerify: cfg.RMQ.TLSSkipVerify,
		ServerName: cfg.RMQ.VerifyServerName,

		Rmq: *opts,
		Log: logger,
	}
	mBus, err := messagebus.New(cfg.RMQurl(), SERVICE_NAME, cfg.RMQ.Readers, &mbOpts)
	if err != nil {
		logger.Fatal("failed to create message bus instance", logging.Fields{"error": err})
	}

	if err := mBus.DeclareQueue(
		cfg.RMQ.FinalStatusQueue.Name,
		messagebus.WithExchange(cfg.RMQ.Exchange),
		messagebus.WithDLExchange(cfg.RMQ.FinalStatusQueue.Name),
	); err != nil {
		fmt.Print("failed to declare main webhook queue: %w", err)
	}

	// We have a bus; let's publish a message to it
	logger.Info("Sending a PUBLISHED notification message to the bus")

	message := datamanager.Notification{
		Id: uuid.New().String(),
		//Id:               "34be8e3b-db7c-4a3c-93ff-16ffa8b2fcf4", // Replace this with an actual v_notification's ID. Look in the v_notifications table in the database
		Status:           datamanager.DeliveryStatus_PUBLISHED,
		Type:             "contact.created",
		TenantId:         uuid.New().String(),
		TenantCustomerId: lo.ToPtr(uuid.New().String()),
		WebhookUrl:       lo.ToPtr("http://localhost:8080/webhook"),
		SigningSecret:    lo.ToPtr(uuid.New().String()),
		CreatedDate:      timestamppb.Now(),
	}

	err = mBus.Send(context.TODO(), cfg.RMQ.FinalStatusQueue.Name, message.ProtoReflect().Interface(), nil)
	if err != nil {
		logger.Fatal("failed to send message to the bus", logging.Fields{"error": err})
	}
}
