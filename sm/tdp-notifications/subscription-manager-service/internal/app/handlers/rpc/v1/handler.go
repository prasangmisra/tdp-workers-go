package v1

import (
	"context"
	"errors"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message"
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	smerrors "github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/errors"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"google.golang.org/protobuf/proto"
)

//go:generate mockery --name IService --output ../../../mock/rest/handlers --outpkg handlersmock
type IService interface {
	CreateSubscription(context.Context, *subscription.SubscriptionCreateRequest) (*subscription.SubscriptionCreateResponse, error)
	DeleteSubscriptionByID(context.Context, *subscription.SubscriptionDeleteRequest) (*subscription.SubscriptionDeleteResponse, error)
	GetSubscriptionByID(context.Context, *subscription.SubscriptionGetRequest) (*subscription.SubscriptionGetResponse, error)
	ListSubscriptions(context.Context, *subscription.SubscriptionListRequest) (*subscription.SubscriptionListResponse, error)
	PauseSubscription(context.Context, *subscription.SubscriptionPauseRequest) (*subscription.SubscriptionPauseResponse, error)
	ResumeSubscription(context.Context, *subscription.SubscriptionResumeRequest) (*subscription.SubscriptionResumeResponse, error)
	UpdateSubscription(context.Context, *subscription.SubscriptionUpdateRequest) (*subscription.SubscriptionUpdateResponse, error)
}

type handler struct {
	s      IService
	logger logger.ILogger
}

func NewHandler(s IService, log logger.ILogger) *handler {
	return &handler{
		s:      s,
		logger: log,
	}
}

func WithErrorReply(handler messagebus.HandlerFuncType, errMessage string) messagebus.HandlerFuncType {
	return func(s messagebus.Server, msg proto.Message) (err error) {
		err = handler(s, msg)
		if err == nil {
			return
		}

		if errors.Is(err, smerrors.ErrInvalidTenantCustomerID) {
			return s.ErrorReply(message.ErrorResponse_BAD_REQUEST, "invalid tenant customer id", err.Error(), false, msg)
		}

		if errors.Is(err, smerrors.ErrNotFound) {
			return s.ErrorReply(message.ErrorResponse_NOT_FOUND, "subscription not found", err.Error(), false, msg)
		}

		if errors.Is(err, smerrors.ErrInvalidNotificationType) {
			return s.ErrorReply(message.ErrorResponse_BAD_REQUEST, "invalid notification type", err.Error(), false, msg)
		}

		return s.ErrorReply(message.ErrorResponse_FAILED_OPERATION, errMessage, err.Error(), false, msg)
	}
}

// Register message handlers for message bus
func (h *handler) Register(bus messagebus.MessageBus) {
	bus.Register(&subscription.SubscriptionCreateRequest{}, WithErrorReply(h.CreateSubscriptionHandler, "error creating subscription"))
	bus.Register(&subscription.SubscriptionDeleteRequest{}, WithErrorReply(h.DeleteSubscriptionByIDHandler, "error deleting subscription"))
	bus.Register(&subscription.SubscriptionGetRequest{}, WithErrorReply(h.GetSubscriptionByIDHandler, "error getting subscription"))
	bus.Register(&subscription.SubscriptionListRequest{}, WithErrorReply(h.ListSubscriptionsHandler, "error getting list of subscriptions"))
	bus.Register(&subscription.SubscriptionPauseRequest{}, WithErrorReply(h.PauseSubscriptionHandler, "error pausing subscription"))
	bus.Register(&subscription.SubscriptionResumeRequest{}, WithErrorReply(h.ResumeSubscriptionHandler, "error resuming subscription"))
	bus.Register(&subscription.SubscriptionUpdateRequest{}, WithErrorReply(h.UpdateSubscriptionHandler, "error updating subscription"))
}
