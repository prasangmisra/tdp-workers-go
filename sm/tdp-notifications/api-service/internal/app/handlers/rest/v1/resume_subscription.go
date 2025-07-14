package v1

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/app/models"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/error_handling"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/messaging"
)

// ResumeSubscriptionHandler godoc
// @Summary		Resume a paused subscription
// @Description	Resumes a subscription by setting its state to "Active". Only Paused subscriptions can be resumed.
// @Tags		subscriptions
// @Accepts		json
// @Produce		json
// @Param		id path string true "Subscription ID"
// @Param		x-version header string true "The API version"
// @Param		x-tenant-customer-id header string true "Tenant customer id"
// @Success		200 {object} models.SubscriptionResumeResponse
// @Failure		400 {object} problem.ProblemDetails
// @Failure		401 {object} problem.ProblemDetails
// @Failure		403 {object} problem.ProblemDetails
// @Failure		404 {object} problem.ProblemDetails
// @Failure		408 {object} problem.ProblemDetails
// @Failure		422 {object} problem.ProblemDetails
// @Failure		429 {object} problem.ProblemDetails
// @Failure		500 {object} problem.ProblemDetails
// @Header		200,400,401,403,404,408,422,429,500	{string} x-transaction-id "Unique request identifier"
// @Header		200,400,401,403,404,408,422,429,500	{int} x-request-duration "Time in seconds it took to receive the response"
// @Header		200,400,401,403,404,408,422,429,500	{int} x-rate-limit "Total number of available requests before being throttled"
// @Header		200,400,401,403,404,408,422,429,500	{int} x-rate-limit-remaining "Remaining number of available requests"
// @Header		200,400,401,403,404,408,422,429,500	{string} x-version "The api version"
// @Header		429 {int} retry-after "Number of seconds to wait before making additional requests"
// @Router		/api/subscriptions/{id}/resume [patch]
func (h *Handler) ResumeSubscriptionHandler(c *gin.Context) {
	params := models.SubscriptionResumeParameter{}

	// Validate URI parameters and bind them to parameters structure
	if err := c.ShouldBindUri(&params); err != nil {
		var ve validator.ValidationErrors
		if errors.As(err, &ve) {
			error_handling.ValidationErrorResponse("", ve, c)
			return
		}
		error_handling.BadRequestErrorResponse("", c)
		return
	}

	// Extract headers
	headers := messaging.GetHeaders(c)

	// Call the service method to pause the subscription
	res, err := h.s.ResumeSubscription(c.Request.Context(), &params, headers, gcontext.GetBaseHeader(c))

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
		error_handling.InternalServerErrorResponse("failed to resume subscription", h.logger, c)
		return
	}

	c.JSON(http.StatusOK, res)
}
