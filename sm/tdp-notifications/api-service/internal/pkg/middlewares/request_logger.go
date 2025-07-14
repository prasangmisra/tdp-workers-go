package middlewares

import (
	"github.com/gin-gonic/gin"
	"github.com/tucowsinc/tdp-shared-go/logger"
)

// RequestLogger Request logger middleware logs the incoming request details
// This middleware will be run for every incoming request
func RequestLogger(log logger.ILogger) gin.HandlerFunc {
	return func(ctx *gin.Context) {
		log.Debug("received request", logger.Fields{
			"remote_addr": ctx.Request.RemoteAddr,
			"protocol":    ctx.Request.Proto,
			"method":      ctx.Request.Method,
			"uri":         ctx.Request.URL.RequestURI(),
		})

		ctx.Next()
	}
}
