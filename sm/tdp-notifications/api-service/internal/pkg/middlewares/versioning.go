package middlewares

import (
	"fmt"
	"net/http"
	"regexp"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/lpar/problem"
)

type Header struct {
	Version *string `header:"x-version" binding:"required"`
}

const versionHeaderName = "x-version"
const defaultVersion = "v1"

var supportedVersions = map[string]bool{"v1": true}

// Versioning reads and validates the X-Version header and
// re-writes the request path to include the provided version
func Versioning(engine *gin.Engine) gin.HandlerFunc {
	return func(context *gin.Context) {
		if !shouldVersionRoute(context) {
			context.Next()
			return
		}

		header := new(Header)
		if err := context.ShouldBindHeader(header); err != nil {
			message := "Missing Version Header"
			versionErrorResponse(message, context)
			return
		}

		version := context.GetHeader(versionHeaderName)
		if version == "" {
			version = defaultVersion
		}

		context.Header(versionHeaderName, version)

		matched, _ := regexp.MatchString("^v\\d+(b\\d+)?$", version)
		if !matched {
			message := "Invalid version header provided"
			versionErrorResponse(message, context)
			return
		}

		// zero value of bool is false so will be false if the version
		// is not in the map
		if !supportedVersions[version] {
			message := "Unsupported Version Header"
			versionErrorResponse(message, context)
			return
		}

		if !hasVersionPrefix(context, version) {

			uriSegments := strings.SplitAfter(context.Request.URL.Path, "/api")
			segments := uriSegments[1:]
			context.Request.URL.Path = fmt.Sprintf("/api/%s%s", version, strings.Join(segments, ""))
			engine.HandleContext(context)
			context.Abort()
		}

		context.Next()
	}
}

// error handling in this middleware is manual and does not make use of the error handling
// middleware, due to a bug that occurs when this middleware is registered
// under the error handling middleware
func versionErrorResponse(message string, context *gin.Context) {
	response := problem.New(http.StatusBadRequest).WithDetail(message)
	response.Type = "https://tools.ietf.org/html/rfc7231#section-6.5.1"
	problem.MustWrite(context.Writer, response)
	context.Abort()
}

// shouldVersionRoute returns false if the route is the default, health or swagger endpoint route
func shouldVersionRoute(context *gin.Context) bool {
	if context.Request.URL.Path == "/" ||
		context.Request.URL.Path == "/health" ||
		strings.HasPrefix(context.Request.URL.Path, "/test") ||
		strings.HasPrefix(context.Request.URL.Path, "/swagger") ||
		context.Request.Method == "OPTIONS" {
		return false
	}
	return true
}

// hasVersionPrefix returns true if a version has been appended to the route, false otherwise
func hasVersionPrefix(context *gin.Context, version string) bool {
	segments := strings.FieldsFunc(context.Request.URL.Path, func(r rune) bool {
		return r == '/'
	})
	for index, segment := range segments {
		if segment == version && index == 1 {
			return true
		}
	}
	return false
}
