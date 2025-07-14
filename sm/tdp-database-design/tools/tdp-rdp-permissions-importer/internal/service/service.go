package service

import (
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/tucowsinc/tdp-shared-go/logger"
)

type service struct {
	db              *pgxpool.Pool
	log             logger.ILogger
	permissionCache map[string]string
}

func New(db *pgxpool.Pool, log logger.ILogger) *service {
	return &service{
		db:              db,
		log:             log,
		permissionCache: make(map[string]string),
	}
}
