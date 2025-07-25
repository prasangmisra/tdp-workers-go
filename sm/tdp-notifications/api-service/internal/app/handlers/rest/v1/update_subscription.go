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

// UpdateSubscriptionHandler godoc
// @Summary		Update a subscription
// @Description	Updates a notifications subscription for domain and contact events.
// @Tags		subscriptions
// @Produces	json
// @Accepts		json
// @Param		id path string true "Subscription ID"
// @Param		idempotency-key header string false "An idempotency key is a unique value generated by the client which the server uses to recognize subsequent retries of the same request. How you Update unique keys is up to you, but we suggest using V4 UUIDs, or another random string with enough entropy to avoid collisions. Idempotency keys can be up to 255 characters long"
// @Param		x-version header string true "The api version"
// @Param		x-tenant-customer-id header string true "Tenant customer id"
// @Param		subscription body models.SubscriptionUpdateRequest true "Subscription to Update"
// @Success		200 {object} models.SubscriptionUpdateResponse
// @Failure		400 {object} problem.ProblemDetails
// @Failure		401 {object} problem.ProblemDetails
// @Failure		403 {object} problem.ProblemDetails
// @Failure		404 {object} problem.ProblemDetails
// @Failure		408 {object} problem.ProblemDetails
// @Failure		429 {object} problem.ProblemDetails
// @Failure		500 {object} problem.ProblemDetails
// @Header		200,400,401,403,404,408,429	{string} x-transaction-id "Unique request identifier"
// @Header		200,400,401,403,404,408,429	{int} x-request-duration "Time in seconds it took to receive the response"
// @Header		200,400,401,403,404,408,429	{int} x-rate-limit "Total number of available requests before being throttled"
// @Header		200,400,401,403,404,408,429	{int} x-rate-limit-remaining "Remaining number of available requests"
// @Header		200,400,401,403,404,408,429	{string} x-version "The api version"
// @Header		429 {int} retry-after "Number of seconds to wait before making additional requests"
// @Router		/api/subscriptions/{id} [patch]
func (h *Handler) UpdateSubscriptionHandler(c *gin.Context) {
	req := models.SubscriptionUpdateRequest{
		ID: c.Param("id"),
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		var ve validator.ValidationErrors
		if errors.As(err, &ve) {
			error_handling.ValidationErrorResponse("", ve, c)
			return
		}

		error_handling.BadRequestErrorResponse("", c)
		return
	}

	headers := messaging.GetHeaders(c)
	res, err := h.s.UpdateSubscription(c.Request.Context(), &req, headers, gcontext.GetBaseHeader(c))

	if errors.Is(err, messagebus.ErrCallTimeout) {
		error_handling.RequestTimeoutResponse("message bus call timeout", c)
		return
	}

	if busErr := new(messaging.BusErr); errors.As(err, &busErr) {
		error_handling.HandleMessageBusErrorResponse(c, h.logger, busErr.ErrorResponse)
		return
	}

	if err != nil {
		error_handling.InternalServerErrorResponse("failed to update subscription", h.logger, c)
		return
	}

	c.JSON(http.StatusOK, res)
}
