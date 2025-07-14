package sqs

import (
	"github.com/alexliesenfeld/health"
)

// HealthCheck creates a new Rabbitmq health check.
func HealthCheck(consumer Consumer) health.Check {
	return health.Check{
		Name:  "SQS",
		Check: consumer.Ping,
	}
}
