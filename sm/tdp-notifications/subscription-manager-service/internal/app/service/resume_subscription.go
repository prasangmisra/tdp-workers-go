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
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
)

func (s *Service) ResumeSubscription(ctx context.Context, req *proto.SubscriptionResumeRequest) (*proto.SubscriptionResumeResponse, error) {
	tenantID, err := s.GetTenantID(ctx, req.TenantCustomerId)
	if err != nil {
		return nil, fmt.Errorf("failed to get TenantID: %w", err)
	}

	activeStatusID := s.subscriptionStatusLT.GetIdByName(model.SubscriptionStatus_Active)
	if activeStatusID == "" {
		return nil, errors.New("failed to get active status id from lookup table")
	}

	var vSubscription *model.VSubscription

	err = s.subDB.WithTransaction(func(tx database.Database) error {
		rowsAffected, err := s.subscriptionViewRepo.Update(ctx, tx,
			&model.VSubscription{
				ID:     req.Id,
				Status: model.SubscriptionStatus_Active,
			},
			repository.Where(&model.VSubscription{
				TenantID: tenantID,
				Type:     lo.ToPtr(model.SubscriptionType_Webhook),
				Status:   model.SubscriptionStatus_Paused,
			}),
		)

		if err != nil {
			return fmt.Errorf("failed to update subscription status: %w", err)
		}

		vSubscription, err = s.subscriptionViewRepo.GetByID(ctx, tx, req.Id, repository.Where(&model.VSubscription{
			TenantID: tenantID,
			Type:     lo.ToPtr(model.SubscriptionType_Webhook),
		}))

		// This would happen if:
		// 1. The subscription does not exist
		// 2. The subscription is not of type webhook
		if errors.Is(err, repository.ErrNotFound) {
			return smerrors.ErrNotFound
		}

		if err != nil {
			return fmt.Errorf("failed to get subscription: %w", err)
		}

		// rowsAffected == 0 means that the subscription was not updated
		// This will be the case when subscription is in a status that cannot be resumed
		if rowsAffected == 0 {
			return smerrors.ErrStatusCannotBeResumed
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	return vSubscription.ToProtoResume()
}
