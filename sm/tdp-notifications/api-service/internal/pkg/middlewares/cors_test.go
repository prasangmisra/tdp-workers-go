package middlewares

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

func setUpTestRouter() *gin.Engine {
	router := gin.New()

	router.Use(CORS())

	router.GET("/", func(ctx *gin.Context) {
		ctx.String(http.StatusOK, "Hello World!")
	})

	return router
}

func TestCorsMiddlewareGetRequest(t *testing.T) {
	gin.SetMode(gin.TestMode)

	req, _ := http.NewRequest("GET", "/", nil)
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Origin", "http://example.com")
	w := httptest.NewRecorder()

	router := setUpTestRouter()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Equal(t, "Hello World!", w.Body.String())
	assert.Equal(t, "*", w.Header().Get("Access-Control-Allow-Origin"))
	assert.Equal(t, "application/json", w.Header().Get("Content-Type"))
	assert.Equal(t, "POST, GET, OPTIONS, PUT, DELETE", w.Header().Get("Access-Control-Allow-Methods"))
	assert.Equal(t, "Accept, Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization", w.Header().Get("Access-Control-Allow-Headers"))
}

func TestCorsMiddlewareOptionsRequest(t *testing.T) {
	gin.SetMode(gin.TestMode)

	req, _ := http.NewRequest("OPTIONS", "/", nil)
	req.Header.Set("Access-Control-Request-Method", "POST")
	req.Header.Set("Access-Control-Request-Headers", "Content-Type")
	req.Header.Set("Origin", "http://example.com")
	w := httptest.NewRecorder()

	router := setUpTestRouter()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusNoContent, w.Code)
	assert.Empty(t, w.Body.String())
	assert.Equal(t, "*", w.Header().Get("Access-Control-Allow-Origin"))
	assert.Equal(t, "application/json", w.Header().Get("Content-Type"))
	assert.Equal(t, "POST, GET, OPTIONS, PUT, DELETE", w.Header().Get("Access-Control-Allow-Methods"))
	assert.Equal(t, "Accept, Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization", w.Header().Get("Access-Control-Allow-Headers"))
}
