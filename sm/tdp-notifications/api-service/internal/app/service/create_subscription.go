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

func (s *Service) CreateSubscription(ctx context.Context, req *models.SubscriptionCreateRequest, headers map[string]any, baseHeader *gcontext.BaseHeader) (*models.SubscriptionCreateResponse, error) {
	subscription, err := req.ToProto(baseHeader)
	if err != nil {
		// We need to make sure to return a special error here so that the handler can respond with a 400
		// TODO: https://wiki-tucows.atlassian.net/browse/DEM-104
		return nil, fmt.Errorf("failed to convert SubscriptionCreateRequest to proto: %w", err)
	}
	_, response, err := s.bus.Call(
		ctx,
		s.subscriptionQ,
		subscription,
		headers,
	)

	if err != nil {
		return nil, fmt.Errorf("failed to send message bus subscription create request %+v: %w", req, err)
	}

	switch m := response.Message.(type) {
	case *subscriptionProto.SubscriptionCreateResponse:
		return models.SubscriptionCreateRespFromProto(m), nil
	case *tcwire.ErrorResponse:
		return nil, &bus.BusErr{ErrorResponse: m}
	default:
		return nil, fmt.Errorf("unexpected message type received %T :%w", m, err)
	}
}
