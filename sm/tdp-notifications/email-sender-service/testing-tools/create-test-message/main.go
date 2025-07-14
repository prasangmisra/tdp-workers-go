// A very basic test program that will drop a simple "EmailSendRequest" message onto the message queue
// which the EmailSenderService will pick up

// TO USE THIS:
// 1. Start the EmailSenderService at least once (so it creates the queue)
// 2. From the command line, `cd` to `tdp-notificaitons/email-sender-service/` directory
// 3. Run `go run testing-tools/create-test-message/main.go`
//
// This will put a message onto the queue.  You can re-run `./create-test-message` as many times as you want; it will just keep putting more messages on the queue
// If you want to change the body of the message, edit the code under the "Create a test message" section below

// This code uses the config file to get the RMQ connection details

package main

import (
	"context"
	"fmt"

	"encoding/json"

	"github.com/tucowsinc/tdp-messages-go/message/common"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"

	"github.com/samber/lo"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	"github.com/tucowsinc/tdp-notifications/email-sender-service/internal/app/config"
	logging "github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/logger/zap"
)

const configPath = "configs"

func main() {

	// Load the config
	config, err := config.LoadConfiguration(configPath)
	logger := zap.NewTdpLogger(config.Log)
	if err != nil {
		logger.Fatal("failed to load configuration", logging.Fields{"error": err})
	}
	ctx := context.Background()

	// Get a connection to the message bus
	mb, err := getMessageBus(&config, logger)
	if err != nil {
		logger.Fatal("failed to create message bus", logging.Fields{"error": err})
	}
	defer mb.Dispose()

	// Create a test message
	emailEnvelope := common.EmailEnvelope{
		Subject:     "Test Email",
		FromAddress: &common.Address{Email: "gng01@tucowsinc.com", Name: lo.ToPtr("Gary")},
		ToAddress:   []*common.Address{{Email: "gng01@tucowsinc.com"}},
	}

	// Data string.  Contains the variables to be plugged into the template
	dataString := "{\"last_name\": \"Bar\", \"first_name\": \"Foo\", \"current_date\": \"2025-04-08T14:02:46-04:00\"}"
	// Convert the data string to a structpb.Struct
	var dataJson map[string]interface{}
	json.Unmarshal([]byte(dataString), &dataJson)
	structValue, _ := structpb.NewStruct(dataJson)
	dataAny, _ := anypb.New(structValue)

	template := "<p><strong>From:</strong> Tucows Inc</p>\n<p><strong>To:</strong> {{ .first_name }} {{ .last_name }}</p>\n<p><strong>Date:</strong> {{ .current_date }}</p>\n<p>Dear {{ .account_name }},</p>\n<p>Your account has been successfully created. Your account ID is {{ .account_id }} and the current status is {{ .account_status }}.</p>\n<p>Thank you for choosing Tucows Inc.</p>\n<p>Just Reusable Test Body</p>\n<p>\n<strong>Tucows Inc</strong><br>\n📍 123 Business St, New York, NY 10001<br>\n📞 <a href=\"tel:+11234567890\">+1 (123) 456-7890</a>\n✉️ <a href=\"mailto:support@yourcompany.com\">support@yourcompany.com</a>\n🌐 <a href=\"https://www.yourcompany.com\">Website</a>\n</p>"

	notification := &datamanager.Notification{
		NotificationDetails: &datamanager.Notification_EmailNotification{
			EmailNotification: &datamanager.EmailNotification{
				Envelope: &emailEnvelope,
				Template: template,
			},
		},
		Data: dataAny,
	}

	// Stick it on the bus
	id, err := mb.Send(ctx, config.RMQ.EmailSendQueue.Name, notification, nil)
	if err != nil {
		logger.Fatal("failed to send message", logging.Fields{"error": err})
	} else {
		logger.Info("message sent", logging.Fields{"id": id})
	}
}

type bus struct {
	messagebus.MessageBus
}

func (b *bus) Dispose() {
	b.MessageBus.Finalize()
}

// Convenience method to return message bus instance
func getMessageBus(cfg *config.Config, logger logging.ILogger) (*bus, error) {

	cfg.RMQ.HostName = "localhost"
	// Create messagebus options
	opts, err := messagebus.NewRabbitMQOptionsBuilder().
		WithExchange(cfg.RMQ.Exchange).
		WithQType(cfg.RMQ.QueueType).
		Build()

	if err != nil {
		logger.Fatal("Error configuring rabbitmq options")
	}

	mbOpts := messagebus.MessageBusOptions{
		CertFile:   cfg.RMQ.CertFile,
		KeyFile:    cfg.RMQ.KeyFile,
		CACertFile: cfg.RMQ.CAFile,
		SkipVerify: cfg.RMQ.TLSSkipVerify,
		ServerName: cfg.RMQ.VerifyServerName,

		Rmq: *opts,
	}

	mBus, err := messagebus.New(cfg.RMQurl(), "enqueuer", cfg.RMQ.Readers, &mbOpts)

	if err != nil {
		return nil, fmt.Errorf("failed to create message bus instance: %w", err)
	}

	if err := mBus.DeclareQueue(
		cfg.RMQ.FinalStatusQueue.Name,
		messagebus.WithExchange(cfg.RMQ.Exchange),
	); err != nil {
		return nil, fmt.Errorf("failed to declare final status queue: %w", err)
	}

	return &bus{MessageBus: mBus}, nil
}
