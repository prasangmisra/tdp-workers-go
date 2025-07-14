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

func (s *Service) GetSubscription(ctx context.Context, req *models.SubscriptionGetParameter, headers map[string]any, baseHeader *gcontext.BaseHeader) (*models.SubscriptionGetResponse, error) {
	// Convert the request to Proto
	subscriptionRequest := req.ToProto(baseHeader)

	_, response, err := s.bus.Call(
		ctx,
		s.subscriptionQ,
		subscriptionRequest,
		headers,
	)

	if err != nil {
		return nil, fmt.Errorf("failed to send message bus subscription get request %+v: %w", req, err)
	}

	switch m := response.Message.(type) {
	case *subscriptionProto.SubscriptionGetResponse:
		return models.SubscriptionGetRespFromProto(m), nil
	case *tcwire.ErrorResponse:
		return nil, &bus.BusErr{ErrorResponse: m}
	default:
		return nil, fmt.Errorf("unexpected message type received %T :%w", m, err)
	}
}
