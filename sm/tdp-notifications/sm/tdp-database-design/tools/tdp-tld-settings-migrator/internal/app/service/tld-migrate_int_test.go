//go:build integration

package service

import (
	"context"
	"fmt"
	"github.com/samber/lo"
	modelcsv "github.com/tucowsinc/tdp-database-design/tools/tdp-tld-settings-migrator/internal/app/model/csv"
	modeldb "github.com/tucowsinc/tdp-database-design/tools/tdp-tld-settings-migrator/internal/app/model/db"
	"github.com/tucowsinc/tdp-shared-go/repository/v3"
)

func (suite *TestSuite) TestMigrateTLD() {
	ctx := context.Background()
	tests := []struct {
		name           string
		records        []*modelcsv.TLDRecordCSV
		fail           bool
		expectedValues []*string
	}{
		{
			name:           "success - no records provided",
			records:        []*modelcsv.TLDRecordCSV{},
			fail:           false,
			expectedValues: make([]*string, 0),
		},
		{
			name: "success - no matching records found",
			records: []*modelcsv.TLDRecordCSV{
				{CategoryName: "cat1", SettingName: "set1", TenantName: "tenant1", TLDName: "tld1", Value: "val1"},
			},
			fail:           false,
			expectedValues: make([]*string, 0),
		},
		{
			name: "success - all matching records for all attr_values types",
			records: []*modelcsv.TLDRecordCSV{
				{CategoryName: "dns", SettingName: "secdns_record_count", TenantName: "opensrs", TLDName: "auto",
					Value: "[1,20)"},
				{CategoryName: "lifecycle", SettingName: "claims_period", TenantName: "opensrs", TLDName: "auto",
					Value: "[2024-12-11 01:01:00+00,infinity]"},
				{CategoryName: "contact", SettingName: "registrant_contact_update_restricted_fields", TenantName: "opensrs", TLDName: "auto",
					Value: "{'txt',''}"},
				{CategoryName: "contact", SettingName: "required_contact_types", TenantName: "opensrs", TLDName: "auto",
					Value: "{}"},
				{CategoryName: "lifecycle", SettingName: "allowed_registration_periods", TenantName: "opensrs", TLDName: "auto",
					Value: "{2,3,5}"},
				{CategoryName: "contact", SettingName: "is_contact_update_supported", TenantName: "opensrs", TLDName: "auto",
					Value: "false"},
				{CategoryName: "dns", SettingName: "max_nameservers", TenantName: "opensrs", TLDName: "auto",
					Value: "1"},
				{CategoryName: "finance", SettingName: "currency", TenantName: "opensrs", TLDName: "auto",
					Value: "CAD"},
			},
			fail: false,
			expectedValues: []*string{
				lo.ToPtr("[1,20)"), lo.ToPtr(`["2024-12-11 01:01:00+00",infinity]`), lo.ToPtr("{'txt',''}"),
				lo.ToPtr("{}"), lo.ToPtr("{2,3,5}"), lo.ToPtr("false"), lo.ToPtr("1"), lo.ToPtr("CAD"),
			},
		},
		{
			name: "success - a mix of not matching and matching records of valid types",
			records: []*modelcsv.TLDRecordCSV{
				{CategoryName: "cat1", SettingName: "set1", TenantName: "tenant1", TLDName: "tld1", Value: "val1"},
				{CategoryName: "finance", SettingName: "currency", TenantName: "opensrs", TLDName: "auto",
					Value: "UAH"},
			},
			fail:           false,
			expectedValues: []*string{lo.ToPtr("UAH")},
		},
		{
			name: "failure - invalid value for type INTEGER_RANGE",
			records: []*modelcsv.TLDRecordCSV{
				{CategoryName: "dns", SettingName: "secdns_record_count", TenantName: "opensrs", TLDName: "auto",
					Value: "invalid"},
			},
			fail: true,
		},
		{
			name: "failure - invalid value for type DATERANGE",
			records: []*modelcsv.TLDRecordCSV{
				{CategoryName: "lifecycle", SettingName: "claims_period", TenantName: "opensrs", TLDName: "auto",
					Value: "invalid"},
			},
			fail: true,
		},
		{
			name: "failure - invalid value for type TEXT_LIST",
			records: []*modelcsv.TLDRecordCSV{
				{CategoryName: "contact", SettingName: "registrant_contact_update_restricted_fields", TenantName: "opensrs", TLDName: "auto",
					Value: "invalid"},
			},
			fail: true,
		},
		{
			name: "failure - invalid value for type INTEGER_LIST",
			records: []*modelcsv.TLDRecordCSV{
				{CategoryName: "lifecycle", SettingName: "allowed_registration_periods", TenantName: "opensrs", TLDName: "auto",
					Value: "invalid"},
			},
			fail: true,
		},
		{
			name: "failure - invalid value for type BOOLEAN",
			records: []*modelcsv.TLDRecordCSV{
				{CategoryName: "contact", SettingName: "is_contact_update_supported", TenantName: "opensrs", TLDName: "auto",
					Value: "invalid"},
			},
			fail: true,
		},
		{
			name: "failure - invalid value for type INTEGER",
			records: []*modelcsv.TLDRecordCSV{
				{CategoryName: "dns", SettingName: "max_nameservers", TenantName: "opensrs", TLDName: "auto",
					Value: "invalid"},
			},
			fail: true,
		},
		{
			name: "failure - a mix of valid and invalid types",
			records: []*modelcsv.TLDRecordCSV{
				{CategoryName: "dns", SettingName: "max_nameservers", TenantName: "opensrs", TLDName: "auto",
					Value: "2"},
				{CategoryName: "dns", SettingName: "max_nameservers", TenantName: "opensrs", TLDName: "auto",
					Value: "invalid"},
			},
			fail: true,
		},
	}
	for _, tt := range tests {
		suite.Run(tt.name, func() {
			valuesBeforeUpd := suite.getTLDConfigValues(ctx, tt.records)
			err := suite.srvc.MigrateTLD(ctx, tt.records)
			if tt.fail {
				suite.Require().Error(err)
				suite.Require().Equal(valuesBeforeUpd, suite.getTLDConfigValues(ctx, tt.records))
				return
			}
			suite.Require().NoError(err)
			suite.Require().Equal(tt.expectedValues, suite.getTLDConfigValues(ctx, tt.records))
		})
	}
}

func (suite *TestSuite) getTLDConfigValues(ctx context.Context, records []*modelcsv.TLDRecordCSV) []*string {
	suite.T().Helper()
	vAttrRepo := repository.New[*modeldb.VAttribute]()
	values := make([]*string, 0, len(records))
	for _, rec := range records {
		attr := &modeldb.VAttribute{
			Key:        lo.ToPtr(fmt.Sprintf("tld.%s.%s", rec.CategoryName, rec.SettingName)),
			TenantName: &rec.TenantName,
			TldName:    &rec.TLDName,
		}
		res, err := vAttrRepo.Find(ctx, suite.db, repository.Where(attr))
		suite.Require().NoError(err)
		for _, v := range res {
			values = append(values, v.Value)
		}
	}
	return values
}
