package service

import (
	"context"
	"fmt"
	"github.com/samber/lo"
	modelcsv "github.com/tucowsinc/tdp-database-design/tools/tdp-tld-settings-migrator/internal/app/model/csv"
	modeldb "github.com/tucowsinc/tdp-database-design/tools/tdp-tld-settings-migrator/internal/app/model/db"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/repository/v3"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
)

func (s *service) MigrateTLD(ctx context.Context, records []*modelcsv.TLDRecordCSV) error {
	var numUpdated int
	err := s.db.WithTransaction(func(tx database.Database) error {
		for i, rec := range records {
			attr := &modeldb.VAttribute{
				Key:        lo.ToPtr(fmt.Sprintf("tld.%s.%s", rec.CategoryName, rec.SettingName)),
				TenantName: &rec.TenantName,
				TldName:    &rec.TLDName,
			}
			rowsAffected, err := s.vAttrRepo.Update(ctx, tx, &modeldb.VAttribute{Value: &rec.Value}, repository.Where(attr))
			if err != nil {
				return fmt.Errorf("failed on the line %d: %w", i+2, err)
			}
			if rowsAffected == 0 {
				s.log.Warn("no tld config found, skipping...", logger.Fields{"line": i + 2})
			} else {
				numUpdated++
			}
		}
		return nil

	})
	if err != nil {
		return fmt.Errorf("failed to update tld configs: %w", err)
	}

	s.log.Info("successfully updated tld configs", logger.Fields{"number updated": numUpdated})
	return nil
}
