package v1

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"
	_ "github.com/lpar/problem"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/app/models"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/error_handling"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/messaging"
)

// GetSubscriptionsHandler retrieves a list of domains based on query parameters.
// @Summary Get a list of subscriptions
// @Description Gets a list of subscriptions based on query parameters.
// @Tags subscriptions
// @Accept json
// @Produce json
// @Param 		x-timeout header int false "The amount of time (seconds) to wait for a sync response. After the timeout has elapsed, the response will be available asynchronously through webhooks."
// @Param 		x-version header string true "The API version"
// @Param		x-tenant-customer-id header string true "Tenant customer id"
// @Param		subscription query models.SubscriptionsGetParameter false "Query params"
// @Success 	200 {object} models.SubscriptionsGetResponse
// @Failure		400 {object} problem.ProblemDetails
// @Failure		401 {object} problem.ProblemDetails
// @Failure		403 {object} problem.ProblemDetails
// @Failure		408 {object} problem.ProblemDetails
// @Failure		429 {object} problem.ProblemDetails
// @Failure		500 {object} problem.ProblemDetails
// @Header		200,400,401,403,408,429	{string} x-transaction-id "Unique request identifier"
// @Header		200,400,401,403,408,429	{int} x-request-duration "Time in seconds it took to receive the response"
// @Header		200,400,401,403,408,429	{int} x-rate-limit "Total number of available requests before being throttled"
// @Header		200,400,401,403,408,429	{int} x-rate-limit-remaining "Remaining number of available requests"
// @Header		200,400,401,403,408,429	{string} x-version "The api version"
// @Header		429 {int} retry-after "Number of seconds to wait before making additional requests"
// @Router /api/subscriptions [get]
func (h *Handler) GetSubscriptionsHandler(c *gin.Context) {
	req := models.SubscriptionsGetParameter{}

	if err := c.ShouldBindQuery(&req); err != nil {
		var ve validator.ValidationErrors
		if errors.As(err, &ve) {
			error_handling.ValidationErrorResponse(err.Error(), ve, c)
			return
		}

		error_handling.BadRequestErrorResponse(err.Error(), c)
		return
	}
	headers := messaging.GetHeaders(c)

	// Call the service method to fetch subscriptions
	res, err := h.s.GetSubscriptions(c.Request.Context(), &req, headers, gcontext.GetBaseHeader(c))

	// Handle message bus timeout
	if errors.Is(err, messagebus.ErrCallTimeout) {
		error_handling.RequestTimeoutResponse("message bus call timeout", c)
		return
	}

	// Handle message bus errors
	if busErr := new(messaging.BusErr); errors.As(err, &busErr) {
		error_handling.HandleMessageBusErrorResponse(c, h.logger, busErr.ErrorResponse)
		return
	}

	if err != nil {
		error_handling.InternalServerErrorResponse("failed to get subscriptions", h.logger, c)
		return
	}

	c.JSON(http.StatusOK, res)
}
