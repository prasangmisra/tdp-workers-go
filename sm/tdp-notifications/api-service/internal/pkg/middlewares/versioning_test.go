package middlewares

import (
	"fmt"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"net/http"
	"net/http/httptest"
	"testing"
)

func setupTestRouter(relativePath string) *gin.Engine {
	router := gin.New()
	router.Use(Versioning(router))

	router.GET(relativePath, func(context *gin.Context) {
		context.String(http.StatusOK, "")
	})

	return router
}

func TestVersioningMiddleware_Ignore_DefaultRoute_When_NoVersionHeaderSpecified(t *testing.T) {
	gin.SetMode(gin.TestMode)

	req, _ := http.NewRequest("GET", "/", nil)
	w := httptest.NewRecorder()

	router := setupTestRouter("/")
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
}

func TestVersioningMiddleware_Ignore_SwaggerRoute_When_NoVersionHeaderSpecified(t *testing.T) {
	gin.SetMode(gin.TestMode)

	req, _ := http.NewRequest("GET", "/swagger/index.html", nil)
	w := httptest.NewRecorder()

	router := setupTestRouter("/swagger/index.html")
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
}

func TestVersioningMiddleware_Ignore_HealthRoute_When_NoVersionHeaderSpecified(t *testing.T) {
	gin.SetMode(gin.TestMode)

	req, _ := http.NewRequest("GET", "/health", nil)
	w := httptest.NewRecorder()

	router := setupTestRouter("/health")
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
}

func TestVersioningMiddleware_Return_400_When_NoVersionHeaderSpecified_For_RequiredRoute(t *testing.T) {
	gin.SetMode(gin.TestMode)

	req, _ := http.NewRequest("GET", "/api/resource", nil)
	w := httptest.NewRecorder()

	router := setupTestRouter("/api/resource")
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusBadRequest, w.Code)
}

func TestVersioningMiddleware_ReturnV1_When_EmptyVersionSpecified(t *testing.T) {
	gin.SetMode(gin.TestMode)

	const defaultVersion = "v1"

	req, _ := http.NewRequest("GET", "/api/resource", nil)
	req.Header.Set(versionHeaderName, "")
	w := httptest.NewRecorder()

	router := setupTestRouter(fmt.Sprintf("/api/%s/resource", defaultVersion))
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Equal(t, defaultVersion, w.Header().Get(versionHeaderName))
}

func TestVersioningMiddleware_Return_400_When_InvalidVersionSpecified(t *testing.T) {
	gin.SetMode(gin.TestMode)

	const version = "invalid-version"

	req, _ := http.NewRequest("GET", "/api/resource", nil)
	req.Header.Set(versionHeaderName, version)
	w := httptest.NewRecorder()

	router := setupTestRouter("/api/resource")
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusBadRequest, w.Code)
	assert.Equal(t, version, w.Header().Get(versionHeaderName))
}

func TestVersioningMiddleware_Return_ProvidedVersion_When_ValidVersionSpecified(t *testing.T) {
	gin.SetMode(gin.TestMode)

	const version = "v1"

	req, _ := http.NewRequest("GET", "/api/resource", nil)
	req.Header.Set(versionHeaderName, version)
	w := httptest.NewRecorder()

	router := setupTestRouter(fmt.Sprintf("/api/%s/resource", version))
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Equal(t, version, w.Header().Get(versionHeaderName))
}

func TestVersioningMiddleware_Unsupported_Version(t *testing.T) {
	gin.SetMode(gin.TestMode)

	const version = "v2"

	req, _ := http.NewRequest("GET", "/api/resource", nil)
	req.Header.Set(versionHeaderName, version)
	w := httptest.NewRecorder()

	router := setupTestRouter(fmt.Sprintf("/api/%s/resource", version))
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusBadRequest, w.Code)
}
