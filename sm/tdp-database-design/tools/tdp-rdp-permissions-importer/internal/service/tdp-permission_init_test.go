//go:build integration

package service

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
	modelcsv "github.com/tucowsinc/tdp-database-design/tools/tdp-rdp-permissions-importer/internal/model/csv"
)

const QueryValidityStart = `
	SELECT TO_CHAR(lower(validity), 'YYYY-MM-DD HH24:MI')
	FROM domain_data_element_permission ddep
	JOIN domain_data_element dde
	JOIN tld t ON t.id = dde.tld_id
	ON dde.id = ddep.domain_data_element_id
	WHERE dde.data_element_id = @data_element_id
	AND t.name = @tld_name
`

func (suite *TestSuite) TestMigrateRDPPermissions() {

	tests := []struct {
		name        string
		records     []*modelcsv.RDPRecord
		tld         string
		setup       func()
		assert      func() error
		wantErr     bool
		errContains string
	}{
		{
			name:        "fail to fetch TLD",
			records:     []*modelcsv.RDPRecord{},
			tld:         "nonexistent-tld", // make sure this value is NOT in your `tld` table
			setup:       nil,               // no setup needed, connection already valid
			assert:      nil,
			wantErr:     true,
			errContains: "failed to find TLD",
		},
		{
			name: "fail to get data element",
			records: []*modelcsv.RDPRecord{
				{
					ContactType:     "invalid-contact-type", // doesn't exist
					DataElementPath: "invalid-element-path",
				},
			},
			tld:         "auto", // must exist in your DB
			setup:       nil,
			assert:      nil,
			wantErr:     true, // the function skips the record and logs error, but doesn't return failure
			errContains: "failed to find data element: no rows in result set",
		},
		{
			name: "Permission not found",
			records: []*modelcsv.RDPRecord{
				{
					DataElementPath: "registrant.first_name",
					Collection:      "must_collects",
				},
			},
			tld:         "auto",
			setup:       nil,
			assert:      nil,
			wantErr:     true,
			errContains: "no permission found with name [must_collects]",
		},
		{
			name: "Success Without Validity",
			records: []*modelcsv.RDPRecord{
				{
					DataElementPath: "registrant.last_name",
					Collection:      "must_collect",
				},
			},
			tld:   "auto",
			setup: nil,
			assert: func() (err error) {
				tx, err := suite.db.Begin(context.Background())
				suite.Require().NoError(err)

				dataElementId, err := suite.srvc.getDataElementId(context.Background(), tx, &modelcsv.RDPRecord{
					DataElementPath: "registrant.last_name",
				})

				suite.Require().NoError(err)

				checkArgs := pgx.NamedArgs{
					"data_element_id": dataElementId,
					"tld_name":        "auto",
				}

				var startDate string

				err = tx.QueryRow(context.Background(), QueryValidityStart, checkArgs).Scan(&startDate)
				suite.Require().NoError(err)
				suite.Require().Equal(time.Now().UTC().Format("2006-01-02 15:04"), startDate)

				return
			},
			wantErr:     false,
			errContains: "",
		},
		{
			name: "Success With Validity",
			records: []*modelcsv.RDPRecord{
				{
					DataElementPath:         "registrant.first_name",
					Collection:              "must_collect",
					CollectionStartValidity: "2030-10-01 00:00",
				},
			},
			tld:   "auto",
			setup: nil,
			assert: func() (err error) {
				tx, err := suite.db.Begin(context.Background())
				suite.Require().NoError(err)

				dataElementId, err := suite.srvc.getDataElementId(context.Background(), tx, &modelcsv.RDPRecord{
					DataElementPath: "registrant.first_name",
				})

				suite.Require().NoError(err)

				checkArgs := pgx.NamedArgs{
					"data_element_id": dataElementId,
					"tld_name":        "auto",
				}

				var validity string

				err = tx.QueryRow(context.Background(), QueryValidityStart, checkArgs).Scan(&validity)
				suite.Require().NoError(err)
				suite.Require().Equal("2030-10-01 00:00", validity)

				return
			},
			wantErr:     false,
			errContains: "",
		},
	}

	for _, tt := range tests {
		suite.Run(tt.name, func() {
			if tt.setup != nil {
				tt.setup()
			}

			err := suite.srvc.MigrateRDPPermissions(context.Background(), tt.records, tt.tld)
			if tt.wantErr {
				suite.Require().Error(err)
				suite.Contains(err.Error(), tt.errContains)
			} else {
				suite.Require().NoError(err)
				if tt.assert != nil {
					tt.assert()
				}
			}
		})
	}
}
