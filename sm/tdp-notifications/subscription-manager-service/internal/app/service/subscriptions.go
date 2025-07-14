package service

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/samber/lo"
	proto "github.com/tucowsinc/tdp-messages-go/message/subscription"
	smerrors "github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/errors"
	"github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/model"
	"github.com/tucowsinc/tdp-shared-go/repository/v3"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
)

func (s *Service) CreateSubscription(ctx context.Context, req *proto.SubscriptionCreateRequest) (*proto.SubscriptionCreateResponse, error) {
	tenantID, err := s.GetTenantID(ctx, req.TenantCustomerId)
	if err != nil {
		return nil, fmt.Errorf("failed to get TenantID: %w", err)
	}

	subscription, err := model.SubscriptionFromProto(req, tenantID)
	if err != nil {
		return nil, fmt.Errorf("error converting create subscription request: %w", err)
	}

	notificationTypes, err := s.notificationTypes("", req.GetNotificationTypes())
	if err != nil {
		return nil, fmt.Errorf("error converting notification types: %w", err)
	}

	var vSubscription *model.VSubscription

	err = s.subDB.WithTransaction(func(tx database.Database) error {
		_, err = s.subscriptionRepo.Create(ctx, tx, subscription)
		if err != nil {
			return fmt.Errorf("failed to create subscription: %w", err)
		}

		webhookChannel := &model.SubscriptionWebhookChannel{
			SubscriptionID: subscription.ID,
			WebhookURL:     req.Url,
			SigningSecret:  uuid.New().String(),
		}

		_, err = s.subscriptionWebhookChannelRepo.Create(ctx, tx, webhookChannel)
		if err != nil {
			return fmt.Errorf("failed to create subscription channel: %w", err)
		}

		lo.ForEach(notificationTypes, func(item *model.SubscriptionNotificationType, _ int) { item.SubscriptionID = subscription.ID })

		_, err = s.subscriptionNotificationTypeRepo.CreateBatch(ctx, tx, &notificationTypes)
		if err != nil {
			return fmt.Errorf("failed to create subscription notification types: %w", err)
		}

		vSubscription, err = s.subscriptionViewRepo.GetByID(ctx, tx, subscription.ID)
		if err != nil {
			return fmt.Errorf("failed to get created subscription entity: %w", err)
		}

		return nil
	})
	if err != nil {
		return nil, err
	}

	return vSubscription.ToProtoCreate()
}

func (s *Service) GetSubscriptionByID(ctx context.Context, req *proto.SubscriptionGetRequest) (*proto.SubscriptionGetResponse, error) {
	tenantID, err := s.GetTenantID(ctx, req.GetTenantCustomerId())
	if err != nil {
		return nil, fmt.Errorf("failed to get TenantID: %w", err)
	}

	vSubscription, err := s.getVSubscriptionByID(ctx, s.subDB, req.GetId(), tenantID)

	if err != nil {
		return nil, fmt.Errorf("failed to get subscription: %w", err)
	}

	return vSubscription.ToProtoGet()
}

func (s *Service) getVSubscriptionByID(ctx context.Context, tx database.Database, id, tenantID string) (*model.VSubscription, error) {
	vSubscription, err := s.subscriptionViewRepo.GetByID(ctx, tx, id, repository.Where(&model.VSubscription{
		TenantID: tenantID,
		Type:     lo.ToPtr(model.SubscriptionType_Webhook),
	}))

	if errors.Is(err, repository.ErrNotFound) {
		return nil, smerrors.ErrNotFound
	}

	return vSubscription, err
}

func (s *Service) ListSubscriptions(ctx context.Context, req *proto.SubscriptionListRequest) (*proto.SubscriptionListResponse, error) {
	tenantID, err := s.GetTenantID(ctx, req.TenantCustomerId)
	if err != nil {
		return nil, fmt.Errorf("failed to get TenantID: %w", err)
	}

	filter := []repository.OptionsFunc{
		repository.Where(&model.VSubscription{
			TenantID: tenantID,
			Type:     lo.ToPtr(model.SubscriptionType_Webhook),
		})}

	var total int64
	if p := req.GetPagination(); p != nil {
		// we need to query total count separately only when we have pagination in request
		total, err = s.subscriptionViewRepo.Count(ctx, s.subDB, filter...)
		if err != nil {
			return nil, fmt.Errorf("failed to get total count of subscriptions: %w", err)
		}

		// no need to proceed - there is no records that satisfy the query
		if total == 0 {
			return &proto.SubscriptionListResponse{}, nil
		}

		// adding pagination to the filter of find query
		filter = append(filter, repository.Pagination(int(p.PageSize), int(p.PageNumber), p.SortBy, p.SortDirection))
	}

	vSubscriptions, err := s.subscriptionViewRepo.Find(ctx, s.subDB, filter...)
	if err != nil {
		return nil, fmt.Errorf("failed to get list of subscriptions: %w", err)
	}

	// means that we have the request without pagination and did not query count separately since it equals the result list length
	if total == 0 {
		total = int64(len(vSubscriptions))
	}

	return model.VSubscriptionListToProto(vSubscriptions, total)
}
