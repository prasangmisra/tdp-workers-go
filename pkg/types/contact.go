package types

type Contact struct {
	Id                 string    `json:"contact_id"`
	Fax                *string   `json:"fax"`
	FaxExt             *string   `json:"fax_ext"`
	Tags               *[]string `json:"tags"`
	Email              *string   `json:"email"`
	Phone              *string   `json:"phone"`
	PhoneExt           *string   `json:"phone_ext"`
	Title              *string   `json:"title"`
	Country            *string   `json:"country"`
	OrgReg             *string   `json:"org_reg"`
	SalesTax           *string   `json:"sales_tax"`
	OrgDuns            *string   `json:"org_duns"`
	Language           *string   `json:"language"`
	ContactType        string    `json:"contact_type"`
	Documentation      *string   `json:"documentation"`
	ContactPostals     []Postal  `json:"contact_postals"`
	TenantCustomerId   string    `json:"tenant_customer_id"`
	CustomerContactRef string    `json:"customer_contact_ref"`
}

type Postal struct {
	City            *string `json:"city"`
	State           *string `json:"state"`
	Address1        *string `json:"address1"`
	Address2        *string `json:"address2"`
	Address3        *string `json:"address3"`
	OrgName         *string `json:"org_name"`
	FirstName       *string `json:"first_name"`
	LastName        *string `json:"last_name"`
	PostalCode      *string `json:"postal_code"`
	IsInternational *bool   `json:"is_international"`
}

type ContactData struct {
	Contact            Contact       `json:"contact"`
	Pw                 string        `json:"pw"`
	Accreditation      Accreditation `json:"accreditation"`
	ProvisionContactId string        `json:"provision_contact_id"`
	TenantCustomerId   string        `json:"tenant_customer_id"`
}

type ContactUpdateData struct {
	Handle                         string        `json:"handle"`
	Contact                        Contact       `json:"contact"`
	Accreditation                  Accreditation `json:"accreditation"`
	ProvisionDomainContactUpdateId string        `json:"provision_domain_contact_update_id"`
	TenantCustomerId               string        `json:"tenant_customer_id"`
}
type ContactDeleteData struct {
	Accreditation Accreditation `json:"accreditation"`
	Handle        string        `json:"handle"`
}
