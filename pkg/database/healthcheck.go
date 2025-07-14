package database

import (
	"github.com/alexliesenfeld/health"
)

// HealthCheck creates a new database connection health check.
func HealthCheck(db Database) health.Check {
	return health.Check{
		Name:  "Database",
		Check: db.Ping,
	}
}
