package middlewares

import (
	"github.com/gin-gonic/gin"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/error_handling"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
)

// ExtractBaseHeaders middleware
func ExtractBaseHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		var baseHeader gcontext.BaseHeader

		if err := c.ShouldBindHeader(&baseHeader); err != nil {
			error_handling.BadRequestErrorResponse("Header validation error: "+err.Error(), c)
			c.Abort()
			return
		}

		baseHeader.SetToGinCtx(c)
		c.Next()
	}
}
