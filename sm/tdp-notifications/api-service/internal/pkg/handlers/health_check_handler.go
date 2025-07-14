package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"net/http"
	"time"

	"github.com/alexliesenfeld/health"
	"github.com/gin-gonic/gin"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/config"
	healthChecks "github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/health_checks"
)

type HealthCheckResponse struct {
	Name string `json:"name"`
	// Overall health status. Can be one of [Healthy], [Degraded] or [Unhealthy]
	Status  string                    `json:"status" example:"Healthy"`
	Details []HealthCheckResponseItem `json:"details"`
} // @name HealthCheckResponse

type HealthCheckResponseItem struct {
	Key         string `json:"key"`
	Description string `json:"description"`
	Status      string `json:"status"`
	Error       string `json:"error"`
} // @name HealthCheckResponseItem

type HandlerResponseWriter struct{}

type checkFunc func(config *config.Config, log logger.ILogger) health.Check

var CheckFunctions = []checkFunc{
	healthChecks.RabbitmqHealthCheck,
}
var SkipOnErr = map[string]bool{}

// HealthCheckHandler godoc
// @Summary		Get the health check information for the api
// @Schemes
// @Description	Gets health check for the api and all dependencies
// @Tags		general
// @Accept		json
// @Produce		json
// @Success		200 {object} HealthCheckResponse
// @Failure		default
// @Router		/health/ [get]
func HealthCheckHandler(config *config.Config, log logger.ILogger) gin.HandlerFunc {
	periodicChecks := []health.CheckerOption{}

	for _, cf := range CheckFunctions {
		periodicChecks = append(periodicChecks, health.WithPeriodicCheck(
			time.Duration(config.HealthCheck.Frequency)*time.Second,
			time.Duration(config.HealthCheck.Latency)*time.Second,
			cf(config, log)),
		)
	}

	healthCheckerOption := []health.CheckerOption{}
	healthCheckerOption = append(healthCheckerOption,
		health.WithTimeout(time.Duration(config.HealthCheck.Timeout)*time.Second),
		health.WithStatusListener(onSystemStatusChangedLog(log)),
	)

	healthCheckerOption = append(healthCheckerOption, periodicChecks...)

	checker := health.NewChecker(
		healthCheckerOption...,
	)

	handler := health.NewHandler(checker,
		health.WithResultWriter(healthCheckResponseWriter()),
		health.WithStatusCodeUp(http.StatusOK),
		health.WithStatusCodeDown(http.StatusServiceUnavailable),
	)

	return gin.WrapH(handler)
}

func onSystemStatusChangedLog(log logger.ILogger) func(ctx context.Context, state health.CheckerState) {
	return func(ctx context.Context, state health.CheckerState) {
		log.Debug("health check system status changed",
			logger.Fields{
				"status": state.Status,
			})
	}
}

func (rw *HandlerResponseWriter) Write(result *health.CheckerResult, statusCode int, w http.ResponseWriter, r *http.Request) error {

	response := parseResponse(result)

	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(statusCode)

	healthCheckResponse, err := json.Marshal(response)
	if err != nil {
		return fmt.Errorf("cannot marshal response: %w", err)
	}

	_, err = w.Write(healthCheckResponse)
	return err
}

func healthCheckResponseWriter() *HandlerResponseWriter {
	return &HandlerResponseWriter{}
}

func parseResponse(result *health.CheckerResult) (response HealthCheckResponse) {
	response.Name = "Self Check"
	response.Status = parseStatusType(health.StatusUp)

	if result.Details != nil {
		for name, details := range result.Details {
			item := HealthCheckResponseItem{Key: name}
			skipErr := SkipOnErr[name]

			if details.Error != nil {
				item.Error = details.Error.Error()
				// API is considered Healthy if non-critical components are down
				if !skipErr {
					response.Status = parseStatusType(health.StatusDown)
				}
			}

			item.Status = parseStatusType(details.Status)

			response.Details = append(response.Details, item)
		}
	}
	return response
}

func parseStatusType(status health.AvailabilityStatus) (st string) {
	st = "Unknown"
	switch status {
	case health.StatusUp:
		st = "Healthy"
	case health.StatusDown:
		st = "Unhealthy"
	case health.StatusUnknown:
		st = "Unknown"
	}
	return
}
