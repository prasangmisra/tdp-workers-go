package messagebus

import (
	"crypto/tls"

	"github.com/alexliesenfeld/health"

	rabbitmqHealthCheck "github.com/tucowsinc/tdp-messagebus-go/pkg/health_checks"
)

// HealthCheck creates a new Rabbitmq health check.
func HealthCheck(url string) health.Check {
	return health.Check{
		Name: "Rabbitmq",
		Check: rabbitmqHealthCheck.NewRabbitmqCheck(rabbitmqHealthCheck.Config{
			DSN: url,
			TLSClientConfig: &tls.Config{
				InsecureSkipVerify: true,
			},
		}),
	}
}
