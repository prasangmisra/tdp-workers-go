package v1

import (
	"context"

	"github.com/gin-gonic/gin"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/app/models"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/middlewares"
	"github.com/tucowsinc/tdp-shared-go/logger"
)

//go:generate mockery --name IService --output ../../../mocks/rest/v1 --outpkg v1restmock
type IService interface {
	CreateSubscription(context.Context, *models.SubscriptionCreateRequest, map[string]any, *gcontext.BaseHeader) (*models.SubscriptionCreateResponse, error)
	DeleteSubscription(context.Context, *models.SubscriptionDeleteParameter, map[string]any, *gcontext.BaseHeader) error
	GetSubscription(context.Context, *models.SubscriptionGetParameter, map[string]any, *gcontext.BaseHeader) (*models.SubscriptionGetResponse, error)
	GetSubscriptions(context.Context, *models.SubscriptionsGetParameter, map[string]any, *gcontext.BaseHeader) (*models.SubscriptionsGetResponse, error)
	PauseSubscription(context.Context, *models.SubscriptionPauseParameter, map[string]any, *gcontext.BaseHeader) (*models.SubscriptionPauseResponse, error)
	ResumeSubscription(context.Context, *models.SubscriptionResumeParameter, map[string]any, *gcontext.BaseHeader) (*models.SubscriptionResumeResponse, error)
	UpdateSubscription(context.Context, *models.SubscriptionUpdateRequest, map[string]any, *gcontext.BaseHeader) (*models.SubscriptionUpdateResponse, error)
	CreateNotification(context.Context, string, map[string]any, *gcontext.BaseHeader) (string, error)
}

type Handler struct {
	s      IService
	logger logger.ILogger
}

func NewHandler(s IService, log logger.ILogger) *Handler {
	return &Handler{
		s:      s,
		logger: log,
	}
}

func (h *Handler) Register(router *gin.RouterGroup) {
	v1Routes := router.Group("v1")
	v1Routes.Use(middlewares.ExtractBaseHeaders())
	v1Routes.POST("/subscriptions", h.CreateSubscriptionHandler)
	v1Routes.POST("/notifications", h.CreateNotificationHandler)
	v1Routes.GET("/subscriptions/:id", h.GetSubscriptionHandler)
	v1Routes.GET("/subscriptions", h.GetSubscriptionsHandler)
	v1Routes.PATCH("/subscriptions/:id", h.UpdateSubscriptionHandler)
	v1Routes.PATCH("/subscriptions/:id/pause", h.PauseSubscriptionHandler)
	v1Routes.PATCH("/subscriptions/:id/resume", h.ResumeSubscriptionHandler)
	v1Routes.DELETE("/subscriptions/:id", h.DeleteSubscriptionHandler)

}
