package service

import (
	"context"
	"errors"

	smerrors "github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/errors"
	"github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/model"
	"github.com/tucowsinc/tdp-shared-go/repository/v3"
)

func (s *Service) GetTenantID(ctx context.Context, tenantCustomerID string) (string, error) {
	tenantCustomer, err := s.tenantCustomerCache.WithCache(tenantCustomerID, func() (*model.VTenantCustomer, error) {
		return s.tenantCustomerRepo.GetByID(ctx, s.domainsDB, tenantCustomerID, repository.Or(&model.VTenantCustomer{CustomerNumber: &tenantCustomerID}))
	})
	if errors.Is(err, repository.ErrNotFound) {
		return "", smerrors.ErrInvalidTenantCustomerID
	}
	if err != nil {
		return "", err
	}

	if tenantID := tenantCustomer.TenantID; tenantID != nil {
		return *tenantID, nil
	}

	return "", smerrors.ErrInvalidTenantCustomerID
}
