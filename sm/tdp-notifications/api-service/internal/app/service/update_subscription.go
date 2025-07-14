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

func (s *Service) UpdateSubscription(ctx context.Context, req *models.SubscriptionUpdateRequest, headers map[string]any, baseHeader *gcontext.BaseHeader) (*models.SubscriptionUpdateResponse, error) {
	subscription, err := req.ToProto(baseHeader)
	if err != nil {
		return nil, fmt.Errorf("failed to convert SubscriptionUpdateRequest to proto: %w", err)
	}
	_, response, err := s.bus.Call(
		ctx,
		s.subscriptionQ,
		subscription,
		headers,
	)

	if err != nil {
		return nil, fmt.Errorf("failed to send message bus subscription update request %+v: %w", req, err)
	}

	switch m := response.Message.(type) {
	case *subscriptionProto.SubscriptionUpdateResponse:
		return models.SubscriptionUpdateRespFromProto(m), nil
	case *tcwire.ErrorResponse:
		return nil, &bus.BusErr{ErrorResponse: m}
	default:
		return nil, fmt.Errorf("unexpected message type received %T :%w", m, err)
	}
}
