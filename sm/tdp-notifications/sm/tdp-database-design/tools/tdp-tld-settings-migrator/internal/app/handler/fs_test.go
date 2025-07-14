package handler

import (
	"context"
	"github.com/stretchr/testify/require"
	handlermock "github.com/tucowsinc/tdp-database-design/tools/tdp-tld-settings-migrator/internal/app/mock/handler"
	modelcsv "github.com/tucowsinc/tdp-database-design/tools/tdp-tld-settings-migrator/internal/app/model/csv"
	"os"
	"testing"
)

func TestHandler_MigrateTLDFromCSV(t *testing.T) {
	ctx := context.Background()
	currentDir, err := os.Getwd()
	require.NoError(t, err)
	tests := []struct {
		name       string
		filePath   string
		mocksF     func(t *testing.T, srvc *handlermock.IService)
		requireErr require.ErrorAssertionFunc
	}{
		{
			name:     "success - parsed file with all types properly",
			filePath: "../../../example.csv",

			mocksF: func(t *testing.T, srvc *handlermock.IService) {
				records := []*modelcsv.TLDRecordCSV{
					{CategoryName: "dns", SettingName: "secdns_record_count", TenantName: "opensrs", TLDName: "auto",
						Value: "[1, 20)"},
					{CategoryName: "lifecycle", SettingName: "claims_period", TenantName: "opensrs", TLDName: "auto",
						Value: "[2024-12-11, infinity]"},
					{CategoryName: "contact", SettingName: "registrant_contact_update_restricted_fields", TenantName: "opensrs", TLDName: "auto",
						Value: "{'txt', ''}"},
					{CategoryName: "contact", SettingName: "required_contact_types", TenantName: "opensrs", TLDName: "auto",
						Value: "{}"},
					{CategoryName: "lifecycle", SettingName: "allowed_registration_periods", TenantName: "opensrs", TLDName: "auto",
						Value: "{2,3,5}"},
					{CategoryName: "contact", SettingName: "is_contact_update_supported", TenantName: "opensrs", TLDName: "auto",
						Value: "FALSE"},
					{CategoryName: "dns", SettingName: "max_nameservers", TenantName: "opensrs", TLDName: "auto",
						Value: "1"},
					{CategoryName: "finance", SettingName: "currency", TenantName: "opensrs", TLDName: "auto",
						Value: "CAD"},
				}
				srvc.On("MigrateTLD", ctx, records).Return(nil).Once()
			},
			requireErr: require.NoError,
		},

		{
			name:     "failures - file not exists",
			filePath: "not-exists.csv",

			mocksF:     func(t *testing.T, srvc *handlermock.IService) {},
			requireErr: require.Error,
		},

		{
			name:     "failures - no csv file",
			filePath: currentDir,

			mocksF:     func(t *testing.T, srvc *handlermock.IService) {},
			requireErr: require.Error,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			srvc := handlermock.NewIService(t)
			tt.mocksF(t, srvc)

			h := New(srvc)
			tt.requireErr(t, h.MigrateTLDFromCSV(ctx, tt.filePath))
		})
	}
}
