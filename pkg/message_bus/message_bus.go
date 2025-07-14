package messagebus

import (
	"context"
	"fmt"
	"time"

	"google.golang.org/protobuf/proto"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	messagebus "github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	tcwire "github.com/tucowsinc/tdp-messages-go/message"
	config "github.com/tucowsinc/tdp-workers-go/pkg/config"
)

const DefaultMessageBusTimeout = 30 // seconds

// SetupMercury sets up the message bus instance using the settings
// read from the configuration object
func SetupMessageBus(cfg config.Config) (mb messagebus.MessageBus, err error) {
	var messageBusOptions messagebus.MessageBusOptions

	rmqOpts, err := messagebus.
		NewRabbitMQOptionsBuilder().
		WithExchange(cfg.RmqExchangeName).
		WithQType(cfg.RmqQueueType).
		Build()

	if err != nil {
		log.Fatal("Error configuring rabbitmq options", log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}

	messageBusOptions = messagebus.MessageBusOptions{
		CertFile:   cfg.RmqCertFile,
		KeyFile:    cfg.RmqKeyFile,
		CACertFile: cfg.RmqCAFile,
		SkipVerify: cfg.RmqTLSSkipVerify,
		ServerName: cfg.RmqVerifyServerName,

		ReadersNumber: cfg.MbReadersCount,

		Rmq: *rmqOpts,
		Log: log.GetLogger(),
	}

	mb, err = messagebus.New(
		cfg.RmqUrl(),
		cfg.RmqQueueName,
		&messageBusOptions,
	)

	return
}

func Call(ctx context.Context, bus messagebus.MessageBus, queue string, msg proto.Message) (interface{}, error) {

	// check if the context has a deadline
	// if not then set default to avoid blocking indefinitely
	rpcCtx := ctx

	var cancel context.CancelFunc
	if _, ok := ctx.Deadline(); !ok {
		rpcCtx, cancel = context.WithTimeout(ctx, DefaultMessageBusTimeout*time.Second)
		defer cancel()
	}

	response, err := bus.Call(rpcCtx, queue, msg, nil)
	if err != nil {
		return nil, fmt.Errorf("error sending message: %w", err)
	}

	if errResp, ok := response.Message.(*tcwire.ErrorResponse); ok {
		return nil, fmt.Errorf("error response from message bus: %s", errResp.Message)
	}

	return response.Message, nil
}
