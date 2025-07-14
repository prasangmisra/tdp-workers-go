package health_checks

import (
	"context"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"time"

	"github.com/alexliesenfeld/health"
	rabbitmqHealthCheck "github.com/tucowsinc/tdp-messagebus-go/pkg/health_checks"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/config"
)

func RabbitmqHealthCheck(config *config.Config, log logger.ILogger) health.Check {
	messageBusOptions := messagebus.MessageBusOptions{
		CertFile:   config.RMQ.CertFile,
		KeyFile:    config.RMQ.KeyFile,
		CACertFile: config.RMQ.CAFile,
		SkipVerify: config.RMQ.TLSSkipVerify,
	}
	tlsConfig, err := messageBusOptions.GetTlsConfig()
	if err != nil {
		log.Error("failed to read tls configs: %v", logger.Fields{"error": err})
		return health.Check{}
	}
	return health.Check{
		Name: "Rabbitmq",
		Check: rabbitmqHealthCheck.NewRabbitmqCheck(rabbitmqHealthCheck.Config{
			DSN:             config.RMQurl(),
			TLSClientConfig: tlsConfig,
		}),
		Timeout: 2 * time.Second,
		StatusListener: func(ctx context.Context, name string, state health.CheckState) {
			log.Debug("health check component status changed",
				logger.Fields{
					"component": name,
					"status":    state.Status,
				})
		},
	}
}
