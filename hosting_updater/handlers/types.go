package handlers

import (
	"context"

	"github.com/alexliesenfeld/health"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/sqs"
	hostingproto "github.com/tucowsinc/tucows-domainshosting-app/cmd/functions/order/proto"
)

type WorkerService struct {
	db       database.Database
	consumer sqs.Consumer
}

// NewWorkerService creates a new instance of WorkerService and configures
// the database and http client used to communicate with the external api
func NewWorkerService(consumer sqs.Consumer, db database.Database) *WorkerService {
	return &WorkerService{
		db:       db,
		consumer: consumer,
	}
}

func SetupSQSConsumer(ctx context.Context, config config.Config) (consumer sqs.Consumer) {
	ob := sqs.NewOptionsBuilder().
		WithDebugModeEnabled(config.IsDebugEnabled()).
		WithQueueName(config.AWSSqsQueueName).
		WithQueueAccountId(config.AWSSqsQueueAccountId).
		WithSSOProfileName(config.AWSSSOProfileName).
		WithAccessKeyId(config.AWSAccessKeyId).
		WithSecretAccessKey(config.AWSSecretAccessKey).
		WithSessionToken(config.AWSSessionToken).
		WithRegion(config.AWSRegion).
		WithRoles(config.AWSRoles)

	options, err := ob.Build()

	if err != nil {
		log.Error("error configuring sqs options", log.Fields{"error": err})
		panic(err)
	}

	consumer, err = sqs.NewConsumer(ctx, *options)
	if err != nil {
		log.Error("error creating sqs consumer instance", log.Fields{"error": err})
		panic(err)
	}

	return
}

// RegisterHandlers registers the handlers for the service.
func (s *WorkerService) RegisterHandlers() {
	s.consumer.Register(
		&hostingproto.OrderDetailsResponse{},
		s.HostingOrderDetailsResponseHandler,
	)
}

// HealthChecks returns a slice of health checks for the service.
func (s *WorkerService) HealthChecks() (checks []health.Check) {
	return []health.Check{
		database.HealthCheck(s.db),
		sqs.HealthCheck(s.consumer),
	}
}
