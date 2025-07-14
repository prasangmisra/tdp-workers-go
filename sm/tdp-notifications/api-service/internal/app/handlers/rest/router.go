package rest

import (
	"github.com/gin-gonic/gin"
	swaggerFiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"
	v1 "github.com/tucowsinc/tdp-notifications/api-service/internal/app/handlers/rest/v1"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/config"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/handlers"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/middlewares"
	"github.com/tucowsinc/tdp-shared-go/logger"
)

func NewRouter(s v1.IService, cfg *config.Config, log logger.ILogger) *gin.Engine {
	router := gin.New()

	router.Use(middlewares.Versioning(router))
	router.Use(middlewares.TimeOut())
	router.Use(middlewares.ErrorHandling(log))
	router.Use(middlewares.CORS())
	router.Use(middlewares.RequestLogger(log))

	router.GET("/", handlers.DefaultHandler())
	router.GET("/health", handlers.HealthCheckHandler(cfg, log))

	router.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))
	ginSwagger.WrapHandler(swaggerFiles.Handler, ginSwagger.URL(cfg.SwaggerURL), ginSwagger.DefaultModelsExpandDepth(-1))

	apiGroup := router.Group("/api")
	v1.NewHandler(s, log).Register(apiGroup)

	return router
}
