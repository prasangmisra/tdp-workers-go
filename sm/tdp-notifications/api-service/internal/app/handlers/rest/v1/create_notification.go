package v1

import (
	"net/http"

	"github.com/gin-gonic/gin"
	_ "github.com/lpar/problem"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/error_handling"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
)

// CreateNotification creates a new notification and places it on the message bus
// @Summary Create notification
// @Description Creates a notification and places it on the message bus
// @Tags notifications
// @Accept json
// @Produce json
// @Param 		x-timeout header int false "The amount of time (seconds) to wait for a sync response. After the timeout has elapsed, the response will be available asynchronously through webhooks."
// @Param 		x-version header string true "The API version"
// @Param		x-tenant-customer-id header string true "Tenant customer id"
// @Param		notification body string true "Notification payload"
// @Success 	200 {object} string
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
// @Router		/api/notifications [post]
func (h *Handler) CreateNotificationHandler(c *gin.Context) {

	res, err := h.s.CreateNotification(c.Request.Context(), "test", nil, gcontext.GetBaseHeader(c))
	if err != nil {
		error_handling.InternalServerErrorResponse("failed to create notification", h.logger, c)
		return
	}

	c.JSON(http.StatusOK, res)
}
