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

func (s *Service) GetSubscriptions(ctx context.Context, req *models.SubscriptionsGetParameter, headers map[string]any, baseHeader *gcontext.BaseHeader) (*models.SubscriptionsGetResponse, error) {
	// Convert the request to Proto
	subscriptionsRequest := req.ToProto(baseHeader)

	_, response, err := s.bus.Call(
		ctx,
		s.subscriptionQ,
		subscriptionsRequest,
		headers,
	)

	if err != nil {
		return nil, fmt.Errorf("failed to send message bus subscriptions get request %+v: %w", req, err)
	}

	switch m := response.Message.(type) {
	case *subscriptionProto.SubscriptionListResponse:
		totalCount := int(m.GetTotalCount())
		return models.SubscriptionsGetRespFromProto(m, &req.Pagination, totalCount), nil
	case *tcwire.ErrorResponse:
		return nil, &bus.BusErr{ErrorResponse: m}
	default:
		return nil, fmt.Errorf("unexpected message type received %T :%w", m, err)
	}
}
