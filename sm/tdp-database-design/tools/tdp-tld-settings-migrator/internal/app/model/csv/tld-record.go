package modelcsv

type TLDRecordCSV struct {
	CategoryName string `csv:"Category Name"`
	SettingName  string `csv:"Setting Name"`
	TenantName   string `csv:"Tenant Name"`
	TLDName      string `csv:"TLD Name"`
	Value        string `csv:"Value to upload"`
}
