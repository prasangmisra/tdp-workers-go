package handler

import (
	"context"
	"github.com/tucowsinc/tdp-database-design/tools/tdp-tld-settings-migrator/internal/app/model/csv"
)

//go:generate mockery --name IService --output ../mock/handler --outpkg handlermock
type IService interface {
	MigrateTLD(context.Context, []*modelcsv.TLDRecordCSV) error
}

type handler struct {
	s IService
}

func New(s IService) *handler {
	return &handler{s: s}
}
