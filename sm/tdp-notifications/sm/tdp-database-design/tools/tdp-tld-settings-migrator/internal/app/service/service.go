package service

import (
	"github.com/tucowsinc/tdp-database-design/tools/tdp-tld-settings-migrator/internal/app/model/db"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/repository/v3"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
)

type service struct {
	db        database.Database
	log       logger.ILogger
	vAttrRepo repository.IRepository[*modeldb.VAttribute]
}

func New(db database.Database, log logger.ILogger) *service {
	return &service{
		db:        db,
		log:       log,
		vAttrRepo: repository.New[*modeldb.VAttribute](),
	}
}
