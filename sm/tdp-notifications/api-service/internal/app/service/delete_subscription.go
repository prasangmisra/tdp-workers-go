package service

import (
	"context"
	"fmt"

	tcwire "github.com/tucowsinc/tdp-messages-go/message"
	subscriptionProto "github.com/tucowsinc/tdp-messages-go/message/subscription"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/app/models"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
	bus "github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/messaging"
)

func (s *Service) DeleteSubscription(ctx context.Context, req *models.SubscriptionDeleteParameter, headers map[string]any, baseHeader *gcontext.BaseHeader) error {
	subscriptionToDelete := req.ToProto(baseHeader)
	_, response, err := s.bus.Call(
		ctx,
		s.subscriptionQ,
		subscriptionToDelete,
		headers,
	)
	if err != nil {
		return fmt.Errorf("failed to send message bus subscription delete request %+v: %w", req, err)
	}
	switch m := response.Message.(type) {
	case *subscriptionProto.SubscriptionDeleteResponse:
		return nil
	case *tcwire.ErrorResponse:
		return &bus.BusErr{ErrorResponse: m}
	default:
		return fmt.Errorf("unexpected message type received %T :%w", m, err)
	}
}
