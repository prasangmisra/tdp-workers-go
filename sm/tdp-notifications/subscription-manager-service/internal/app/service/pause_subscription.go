package service

import (
	"context"
	"errors"
	"fmt"

	"github.com/samber/lo"
	proto "github.com/tucowsinc/tdp-messages-go/message/subscription"
	smerrors "github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/errors"
	"github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/model"
	"github.com/tucowsinc/tdp-shared-go/repository/v3"
)

func (s *Service) PauseSubscription(ctx context.Context, req *proto.SubscriptionPauseRequest) (*proto.SubscriptionPauseResponse, error) {
	tenantID, err := s.GetTenantID(ctx, req.TenantCustomerId)
	if err != nil {
		return nil, fmt.Errorf("failed to get TenantID: %w", err)
	}

	pausedStatusID := s.subscriptionStatusLT.GetIdByName(model.SubscriptionStatus_Paused)
	if pausedStatusID == "" {
		return nil, errors.New("failed to get paused status id from lookup table")
	}

	vSubscription := &model.VSubscription{
		ID:     req.Id,
		Status: model.SubscriptionStatus_Paused,
	}

	rowsAffected, err := s.subscriptionViewRepo.Update(ctx, s.subDB,
		vSubscription,
		repository.Where(&model.VSubscription{
			TenantID: tenantID,
			Type:     lo.ToPtr(model.SubscriptionType_Webhook),
			Status:   model.SubscriptionStatus_Active,
		}),
		repository.Or(&model.VSubscription{
			TenantID: tenantID,
			Type:     lo.ToPtr(model.SubscriptionType_Webhook),
			Status:   model.SubscriptionStatus_Degraded,
		}),
		repository.Returning(),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to update subscription status: %w", err)
	}
	if rowsAffected > 0 {
		return vSubscription.ToProtoPause()
	}

	// filter without status to see if the subscription exists at all
	num, err := s.subscriptionViewRepo.Count(ctx, s.subDB, repository.Where(&model.VSubscription{
		ID:       req.Id,
		TenantID: tenantID,
		Type:     lo.ToPtr(model.SubscriptionType_Webhook),
	}))

	if err != nil {
		return nil, fmt.Errorf("failed to get subscriptions number: %w", err)
	}

	// This would happen if:
	// 1. The subscription does not exist
	// 2. The subscription is not of type webhook
	if num == 0 {
		return nil, smerrors.ErrNotFound
	}

	// the only other possible reason why no rows were updated is when subscription is in a wrong status
	return nil, smerrors.ErrStatusCannotBePaused
}
