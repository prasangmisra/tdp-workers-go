package service

import (
	"context"
	"errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	modelcsv "github.com/tucowsinc/tdp-database-design/tools/tdp-tld-settings-migrator/internal/app/model/csv"
	modeldb "github.com/tucowsinc/tdp-database-design/tools/tdp-tld-settings-migrator/internal/app/model/db"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/mocks"
	"testing"
)

func TestCreateOrder(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	rec1 := &modelcsv.TLDRecordCSV{CategoryName: "cat1", SettingName: "set1", TenantName: "tenant1", TLDName: "tld1", Value: "val1"}
	rec2 := &modelcsv.TLDRecordCSV{CategoryName: "cat2", SettingName: "set2", TenantName: "tenant2", TLDName: "tld2", Value: "val2"}

	tests := []struct {
		name    string
		records []*modelcsv.TLDRecordCSV
		mocksF  func(t *testing.T, db *database.MockDatabase, vAttrRepo *mocks.IRepository[*modeldb.VAttribute])

		requireErr require.ErrorAssertionFunc
	}{
		{
			name:    "success - both records are updated",
			records: []*modelcsv.TLDRecordCSV{rec1, rec2},
			mocksF: func(t *testing.T, db *database.MockDatabase, vAttrRepo *mocks.IRepository[*modeldb.VAttribute]) {
				// expect to commit transaction
				tx := db.OnTransaction(t, database.WithCommit(nil))

				// expect to run in transaction - so expect the tx
				vAttrRepo.On("Update", ctx, tx, &modeldb.VAttribute{Value: &rec1.Value}, mock.AnythingOfType("repository.OptionsFunc")).
					Return(int64(1), nil).Times(1)
				vAttrRepo.On("Update", ctx, tx, &modeldb.VAttribute{Value: &rec2.Value}, mock.AnythingOfType("repository.OptionsFunc")).
					Return(int64(1), nil).Times(1)
			},

			requireErr: require.NoError,
		},
		{
			name:    "success - only first record is updated",
			records: []*modelcsv.TLDRecordCSV{rec1, rec2},
			mocksF: func(t *testing.T, db *database.MockDatabase, vAttrRepo *mocks.IRepository[*modeldb.VAttribute]) {
				// expect to commit transaction
				tx := db.OnTransaction(t, database.WithCommit(nil))

				// expect to run in transaction - so expect the tx
				vAttrRepo.On("Update", ctx, tx, &modeldb.VAttribute{Value: &rec1.Value}, mock.AnythingOfType("repository.OptionsFunc")).
					Return(int64(1), nil).Times(1)
				vAttrRepo.On("Update", ctx, tx, &modeldb.VAttribute{Value: &rec2.Value}, mock.AnythingOfType("repository.OptionsFunc")).
					Return(int64(0), nil).Times(1)
			},

			requireErr: require.NoError,
		},
		{
			name:    "success - only second record is updated",
			records: []*modelcsv.TLDRecordCSV{rec1, rec2},
			mocksF: func(t *testing.T, db *database.MockDatabase, vAttrRepo *mocks.IRepository[*modeldb.VAttribute]) {
				// expect to commit transaction
				tx := db.OnTransaction(t, database.WithCommit(nil))

				// expect to run in transaction - so expect the tx
				vAttrRepo.On("Update", ctx, tx, &modeldb.VAttribute{Value: &rec1.Value}, mock.AnythingOfType("repository.OptionsFunc")).
					Return(int64(0), nil).Times(1)
				vAttrRepo.On("Update", ctx, tx, &modeldb.VAttribute{Value: &rec2.Value}, mock.AnythingOfType("repository.OptionsFunc")).
					Return(int64(1), nil).Times(1)
			},

			requireErr: require.NoError,
		},
		{
			name:    "success - no records were updated",
			records: []*modelcsv.TLDRecordCSV{rec1, rec2},
			mocksF: func(t *testing.T, db *database.MockDatabase, vAttrRepo *mocks.IRepository[*modeldb.VAttribute]) {
				// expect to commit transaction
				tx := db.OnTransaction(t, database.WithCommit(nil))

				// expect to run in transaction - so expect the tx
				vAttrRepo.On("Update", ctx, tx, &modeldb.VAttribute{Value: &rec1.Value}, mock.AnythingOfType("repository.OptionsFunc")).
					Return(int64(0), nil).Times(1)
				vAttrRepo.On("Update", ctx, tx, &modeldb.VAttribute{Value: &rec2.Value}, mock.AnythingOfType("repository.OptionsFunc")).
					Return(int64(0), nil).Times(1)
			},

			requireErr: require.NoError,
		},
		{
			name:    "fail - db error on the first record",
			records: []*modelcsv.TLDRecordCSV{rec1, rec2},
			mocksF: func(t *testing.T, db *database.MockDatabase, vAttrRepo *mocks.IRepository[*modeldb.VAttribute]) {
				// expect to roll back the transaction
				tx := db.OnTransaction(t, database.WithRollback(nil))

				// expect to run in transaction - so expect the tx
				vAttrRepo.On("Update", ctx, tx, &modeldb.VAttribute{Value: &rec1.Value}, mock.AnythingOfType("repository.OptionsFunc")).
					Return(int64(0), errors.New("db error")).Times(1)
			},

			requireErr: require.Error,
		},
		{
			name:    "fail - db error on the second record",
			records: []*modelcsv.TLDRecordCSV{rec1, rec2},
			mocksF: func(t *testing.T, db *database.MockDatabase, vAttrRepo *mocks.IRepository[*modeldb.VAttribute]) {
				// expect to roll back the transaction
				tx := db.OnTransaction(t, database.WithRollback(nil))

				// expect to run in transaction - so expect the tx
				vAttrRepo.On("Update", ctx, tx, &modeldb.VAttribute{Value: &rec1.Value}, mock.AnythingOfType("repository.OptionsFunc")).
					Return(int64(1), nil).Times(1)
				vAttrRepo.On("Update", ctx, tx, &modeldb.VAttribute{Value: &rec2.Value}, mock.AnythingOfType("repository.OptionsFunc")).
					Return(int64(0), errors.New("db error")).Times(1)
			},

			requireErr: require.Error,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			mockDB, mockVAttrRepo := database.NewMockDatabase(t), mocks.NewIRepository[*modeldb.VAttribute](t)
			s := service{db: mockDB, vAttrRepo: mockVAttrRepo, log: &logger.MockLogger{}}
			if tc.mocksF != nil {
				tc.mocksF(t, mockDB, mockVAttrRepo)
			}

			err := s.MigrateTLD(ctx, tc.records)
			tc.requireErr(t, err)
		})
	}
}
