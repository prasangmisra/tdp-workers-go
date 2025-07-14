package service

import (
	"fmt"

	"github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/config"
	"github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/model"
	"github.com/tucowsinc/tdp-shared-go/memoizelib"
	"github.com/tucowsinc/tdp-shared-go/repository/v3"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
)

type Service struct {
	domainsDB, subDB database.Database

	subscriptionRepo                 repository.IRepository[*model.Subscription]
	subscriptionViewRepo             repository.IRepository[*model.VSubscription]
	subscriptionWebhookChannelRepo   repository.IRepository[*model.SubscriptionWebhookChannel]
	subscriptionNotificationTypeRepo repository.IRepository[*model.SubscriptionNotificationType]
	tenantCustomerRepo               repository.IRepository[*model.VTenantCustomer]

	notificationTypeLT   repository.ILookupTable[*model.NotificationType]
	subscriptionStatusLT repository.ILookupTable[*model.SubscriptionStatus]
	tenantCustomerCache  memoizelib.Cached[*model.VTenantCustomer]
}

func New(domainsDB, subDB database.Database, cfg *config.Config) (*Service, error) {
	notificationTypeLT, err := repository.NewLookupTable[*model.NotificationType](subDB)
	if err != nil {
		return nil, fmt.Errorf("failed to instantiate notification_type lookup table: %w", err)
	}

	subscriptionStatusLT, err := repository.NewLookupTable[*model.SubscriptionStatus](subDB)
	if err != nil {
		return nil, fmt.Errorf("failed to instantiate subscription_status lookup table: %w", err)
	}

	return &Service{
		domainsDB:                        domainsDB,
		subDB:                            subDB,
		notificationTypeLT:               notificationTypeLT,
		subscriptionStatusLT:             subscriptionStatusLT,
		subscriptionRepo:                 repository.New[*model.Subscription](),
		subscriptionViewRepo:             repository.New[*model.VSubscription](),
		subscriptionWebhookChannelRepo:   repository.New[*model.SubscriptionWebhookChannel](),
		subscriptionNotificationTypeRepo: repository.New[*model.SubscriptionNotificationType](),
		tenantCustomerRepo:               repository.New[*model.VTenantCustomer](),
		tenantCustomerCache:              memoizelib.New[*model.VTenantCustomer](cfg.Cache.LifetimeSec, cfg.Cache.MaxKeys),
	}, err
}
