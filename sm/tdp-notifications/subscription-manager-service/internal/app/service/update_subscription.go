package service

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/samber/lo"
	proto "github.com/tucowsinc/tdp-messages-go/message/subscription"
	smerrors "github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/errors"
	"github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/model"
	"github.com/tucowsinc/tdp-shared-go/repository/v3"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/suboptions/onconflict"
)

func (s *Service) notificationTypeIDs(names []string) ([]string, error) {
	ids := make([]string, 0, len(names))
	for _, name := range names {
		id := s.notificationTypeLT.GetIdByName(name)
		if id == "" {
			return nil, fmt.Errorf("%w: %s", smerrors.ErrInvalidNotificationType, name)
		}
		ids = append(ids, id)
	}
	return ids, nil
}

func (s *Service) notificationTypes(subID string, names []string) ([]*model.SubscriptionNotificationType, error) {
	types := make([]*model.SubscriptionNotificationType, 0, len(names))
	for _, name := range names {
		lookupname := strings.ToLower(name) // Database content should always be lowercase (see test-data.sql)
		id := s.notificationTypeLT.GetIdByName(lookupname)
		if id == "" {
			return nil, fmt.Errorf("%w: %s", smerrors.ErrInvalidNotificationType, name)
		}
		types = append(types, &model.SubscriptionNotificationType{TypeID: id, SubscriptionID: subID})
	}
	return types, nil
}

func (s *Service) UpdateSubscription(ctx context.Context, req *proto.SubscriptionUpdateRequest) (*proto.SubscriptionUpdateResponse, error) {
	vSubUpdate, err := model.VSubscriptionFromProtoUpdate(req)
	if err != nil {
		return nil, fmt.Errorf("error converting update subscription request: %w", err)
	}

	if vSubUpdate == nil && len(req.GetRemNotificationTypes())+len(req.GetAddNotificationTypes()) == 0 {
		return nil, smerrors.ErrInvalidRequest
	}

	subID := req.GetId()
	addTypes, err := s.notificationTypes(subID, req.GetAddNotificationTypes())
	if err != nil {
		return nil, fmt.Errorf("error converting notification types to add: %w", err)
	}

	remTypeIDs, err := s.notificationTypeIDs(req.GetRemNotificationTypes())
	if err != nil {
		return nil, fmt.Errorf("error getting notification type IDs to remove: %w", err)
	}

	tenantID, err := s.GetTenantID(ctx, req.GetTenantCustomerId())
	if err != nil {
		return nil, fmt.Errorf("failed to get TenantID: %w", err)
	}

	err = s.subDB.WithTransaction(func(tx database.Database) error {
		if err := s.updateNotificationTypes(ctx, tx, subID, tenantID, addTypes, remTypeIDs); err != nil {
			return fmt.Errorf("failed to update subscription notification types: %w", err)
		}

		if vSubUpdate == nil {
			vSubUpdate, err = s.getVSubscriptionByID(ctx, tx, subID, tenantID)
			if err != nil {
				return fmt.Errorf("failed to get subscription after update: %w", err)
			}
			return nil
		}

		rowsAffected, err := s.subscriptionViewRepo.Update(ctx, tx,
			vSubUpdate,
			repository.Where(&model.VSubscription{
				TenantID: tenantID,
				Type:     lo.ToPtr(model.SubscriptionType_Webhook),
			}),
			repository.Returning(),
		)

		if err != nil {
			return fmt.Errorf("failed to update subscription: %w", err)
		}

		if rowsAffected == 0 {
			return smerrors.ErrNotFound
		}

		return nil
	})

	if err != nil {
		return nil, fmt.Errorf("failed to update subscription: %w", err)
	}

	return vSubUpdate.ToProtoUpdate()
}

func (s *Service) updateNotificationTypes(ctx context.Context, tx database.Database, subID, tenantID string,
	addTypes []*model.SubscriptionNotificationType, remTypeIDs []string) error {
	if len(remTypeIDs)+len(addTypes) == 0 {
		return nil
	}

	// make sure subscription exists and is not deleted
	sCount, err := s.subscriptionViewRepo.Count(ctx, tx,
		repository.Where(&model.VSubscription{
			ID:       subID,
			TenantID: tenantID,
			Type:     lo.ToPtr(model.SubscriptionType_Webhook),
		}),
	)

	if err != nil {
		return fmt.Errorf("failed to get subscription count to make sure that subscription exists: %w", err)
	}

	if sCount == 0 {
		return smerrors.ErrNotFound
	}

	if len(addTypes) > 0 {
		_, err := s.subscriptionNotificationTypeRepo.CreateBatch(ctx, tx, &addTypes,
			repository.OnConflict(onconflict.DoNothing()))

		if err != nil {
			return fmt.Errorf("failed to add subscription notification types: %w", err)
		}
	}

	if len(remTypeIDs) == 0 {
		return nil
	}

	_, err = s.subscriptionNotificationTypeRepo.Delete(ctx, tx, &model.SubscriptionNotificationType{},
		repository.Where(&model.SubscriptionNotificationType{SubscriptionID: subID}),
		repository.Where("type_id IN (?)", remTypeIDs))

	if err != nil {
		return fmt.Errorf("failed to delete subscription notification types: %w", err)
	}

	// subscription without notification types is not allowed
	ntCount, err := s.subscriptionNotificationTypeRepo.Count(ctx, tx, repository.Where(&model.SubscriptionNotificationType{SubscriptionID: subID}))
	if err != nil {
		return fmt.Errorf("failed to count subscription notification types after removal: %w", err)
	}

	if ntCount == 0 {
		return errors.New("removing all subscription notification types is not allowed")
	}

	return nil
}
