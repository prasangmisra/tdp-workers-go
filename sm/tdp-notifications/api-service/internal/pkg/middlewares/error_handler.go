package middlewares

import (
	"fmt"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"net/http"
	"runtime/debug"

	"github.com/gin-gonic/gin"
	"github.com/lpar/problem"
)

// ErrorHandling handles all the exceptions in the application and provides a consistent
// response to the client. The response if of type ProblemDetails (RFC-7807, RFC-7231)
func ErrorHandling(log logger.ILogger) gin.HandlerFunc {
	return func(context *gin.Context) {
		defer func() {
			var err error
			if rec := recover(); rec != nil {
				var ok bool
				if err, ok = rec.(error); !ok {
					err = fmt.Errorf("%v", rec)
				}
			}

			if err != nil {
				if gin.Mode() == gin.DebugMode {
					log.Error("unhandled error occurred ", logger.Fields{
						"error": err,
						"stack": string(debug.Stack()),
					})
				}
				problem.MustWrite(context.Writer, createInternalServerProblemDetails(err.Error()))
				return
			}

			for _, e := range context.Errors {
				switch e.Err.(type) {
				case *problem.ProblemDetails, *problem.ValidationProblem:
					err = problem.MustWrite(context.Writer, e.Err)
					log.Info(" context error", logger.Fields{"error": err})
				default:
					problem.MustWrite(context.Writer, createInternalServerProblemDetails(e.Err.Error()))
				}
			}
		}()

		context.Next()
	}
}

func createInternalServerProblemDetails(message string) (pd *problem.ProblemDetails) {
	pd = problem.New(http.StatusInternalServerError).WithDetail(message)
	pd.Type = "https://www.rfc-editor.org/rfc/rfc7231#section-6.6.1"
	return
}
