package handler

import (
	"context"

	modelcsv "github.com/tucowsinc/tdp-database-design/tools/tdp-rdp-permissions-importer/internal/model/csv"
)

type IService interface {
	MigrateRDPPermissions(context.Context, []*modelcsv.RDPRecord, string) error
}

type handler struct {
	s IService
}

func New(s IService) *handler {
	return &handler{
		s: s,
	}
}
