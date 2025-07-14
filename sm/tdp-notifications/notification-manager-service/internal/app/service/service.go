package service

import (
	"github.com/tucowsinc/tdp-notifications/notification-manager-service/internal/app/model"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/repository/v3"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
)

type Service struct {
	subDB             database.Database
	vnotificationRepo repository.IRepository[*model.VNotification]
	logger            logger.ILogger
}

func New(log logger.ILogger, subDB database.Database) (*Service, error) {
	return &Service{
		subDB:             subDB,
		vnotificationRepo: repository.New[*model.VNotification](),
		logger:            log,
	}, nil
}
