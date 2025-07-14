package middlewares

import (
	"github.com/gin-gonic/gin"
	"net/http"
)

// CORS or Cross-Origin Resource Sharing middleware configures CORS
// related settings for the incoming requests. For OPTIONS request
// a default 204 status code is returned
func CORS() gin.HandlerFunc {
	return func(ctx *gin.Context) {
		ctx.Writer.Header().Add("Access-Control-Allow-Origin", "*")
		ctx.Writer.Header().Add("Content-Type", "application/json")
		ctx.Writer.Header().Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS, PUT, DELETE")
		ctx.Writer.Header().Set("Access-Control-Allow-Headers", "Accept, Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization")

		if ctx.Request.Method == "OPTIONS" {
			ctx.AbortWithStatus(http.StatusNoContent)
			return
		}

		ctx.Next()
	}
}
