package service

import (
	"context"
	"fmt"

	"github.com/samber/lo"
	proto "github.com/tucowsinc/tdp-messages-go/message/subscription"
	smerrors "github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/errors"
	"github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/model"
	"github.com/tucowsinc/tdp-shared-go/repository/v3"
)

func (s *Service) DeleteSubscriptionByID(ctx context.Context, req *proto.SubscriptionDeleteRequest) (*proto.SubscriptionDeleteResponse, error) {
	tenantID, err := s.GetTenantID(ctx, req.TenantCustomerId)
	if err != nil {
		return nil, fmt.Errorf("failed to get TenantID: %w", err)
	}

	// this will be converted into the update query as we do a soft delete, so we can use the existing update trigger on the view
	rowsAffected, err := s.subscriptionViewRepo.Delete(ctx, s.subDB,
		&model.VSubscription{ID: req.Id},
		repository.Where(&model.VSubscription{
			TenantID: tenantID,
			Type:     lo.ToPtr(model.SubscriptionType_Webhook),
		}),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to delete subscription: %w", err)
	}

	// No such webhook subscription exists
	if rowsAffected == 0 {
		return nil, smerrors.ErrNotFound
	}

	return &proto.SubscriptionDeleteResponse{}, nil
}
