package rpc

import (
	"fmt"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/config"
	"github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/handlers/rpc/v1"
	"github.com/tucowsinc/tdp-shared-go/logger"
)

// bus is a struct that manages the connection to a RabbitMQ message bus.
// It contains a field of type messagebus.MessageBus which is used to interact with the RabbitMQ server.
// The message bus is initialized with the configuration provided when creating a new instance of Bus.
//
// Fields:
// It has an embedded instance of messagebus.MessageBus.
type bus struct {
	messagebus.MessageBus
}

// New creates a new instance of Bus.
// It takes a Config struct as an argument, which contains the configuration for the RabbitMQ message bus.
// The function initializes a new RabbitMQ message bus with the provided configuration.
// The message bus is then assigned to the Bus field of the Bus struct.
// The function returns a pointer to the newly created Bus.
//
// Parameters:
// cfg: A Config struct that contains the configuration for the RabbitMQ message bus. The configuration includes the RabbitMQ URL, exchange, queue type, queue name, and number of readers.
//
// Returns:
// *bus: A pointer to the newly created Bus.
// error: An error if there was an issue during the operation, nil otherwise.
func New(cfg *config.Config, s v1.IService, log logger.ILogger) (*bus, error) {
	opts, err := messagebus.NewRabbitMQOptionsBuilder().
		WithExchange(cfg.RMQ.Exchange).
		WithQType(cfg.RMQ.QueueType).
		Build()

	if err != nil {
		return nil, fmt.Errorf("failed to build message bus options: %w", err)
	}

	mbOpts := messagebus.MessageBusOptions{
		CertFile:   cfg.RMQ.CertFile,
		KeyFile:    cfg.RMQ.KeyFile,
		CACertFile: cfg.RMQ.CAFile,
		SkipVerify: cfg.RMQ.TLSSkipVerify,
		ServerName: cfg.RMQ.VerifyServerName,

		Rmq: *opts,
	}

	mBus, err := messagebus.New(cfg.RMQurl(), cfg.RMQ.QueueName, cfg.RMQ.Readers, &mbOpts)

	if err != nil {
		return nil, fmt.Errorf("failed to create message bus instance: %w", err)
	}

	v1.NewHandler(s, log).Register(mBus)

	return &bus{MessageBus: mBus}, nil
}

// Dispose closes the connection to the RabbitMQ message bus.
// It calls the Finalize method on the messagebus.MessageBus which releases any resources associated with the message bus.
// This function should be called when the Bus is no longer needed.
func (b *bus) Dispose() {
	b.MessageBus.Finalize()
}
