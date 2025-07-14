// This module implements the database model (ORM)
// for tdpdb
//
// This is an automatically generated file, do not edit
// by hand.
//
// schemadump options:
//
//	'--dbhost' 'localhost' '--dbname' 'tdpdb' '--dbport' '5432' '--dbuser'
//	'tucows' '--dbpass' 'tucows1234' '--pgx' '--target-dir'
//	'../../orm/go/domainsdb'
//
// Generated On:
//
//	Fri Mar 31 13:45:03 2023
package db

import (
	"fmt"
	"os"
	"time"

	"github.com/jmoiron/sqlx/types"
	"github.com/lib/pq"

	"github.com/jinzhu/gorm"
	"github.com/lib/pq"

	// blank import needed to load the driver
	_ "github.com/jinzhu/gorm/dialects/postgres"
)

// Connect connects to the postgres database using
// the url string
func Connect(url string) (*gorm.DB, error) {

	connectString := fmt.Sprintf("%s ", url)
	logging := false

	if os.Getenv("QUERY_TRACE") == "1" {
		logging = true
	}

	db, err := gorm.Open("postgres", connectString)

	if err != nil {
		return nil, err
	}

	db.SingularTable(true)
	db.LogMode(logging)

	return db, nil
}

// Table Definitions

// Accreditation

type Accreditation struct {
	CreatedBy          *string    `db:"created_by" json:"created_by"`
	CreatedDate        *time.Time `db:"created_date" json:"created_date"`
	Id                 string     `db:"id" json:"id"`
	Name               string     `db:"name" json:"name"`
	ProviderInstanceId string     `db:"provider_instance_id" json:"provider_instance_id"`
	// This attribute serves to limit the applicability of a relation
	// over time.
	ServiceRange string     `db:"service_range" json:"service_range"`
	TenantId     string     `db:"tenant_id" json:"tenant_id"`
	UpdatedBy    *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate  *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	Tenant           *Tenant           `json:"tenant"`
	ProviderInstance *ProviderInstance `json:"provider_instance"`

	// has many
	AccreditationEpps []AccreditationEpp `json:"accreditation_epps"`
	AccreditationTlds []AccreditationTld `json:"accreditation_tlds"`
}

// TableName sets the table name
func (Accreditation) TableName() string {
	return "accreditation"
}

// AccreditationEpp

type AccreditationEpp struct {
	AccreditationId string     `db:"accreditation_id" json:"accreditation_id"`
	CertId          *string    `db:"cert_id" json:"cert_id"`
	Clid            string     `db:"clid" json:"clid"`
	ConnMax         *int       `db:"conn_max" json:"conn_max"`
	ConnMin         *int       `db:"conn_min" json:"conn_min"`
	CreatedBy       *string    `db:"created_by" json:"created_by"`
	CreatedDate     *time.Time `db:"created_date" json:"created_date"`
	Host            *string    `db:"host" json:"host"`
	Id              string     `db:"id" json:"id"`
	Port            *int       `db:"port" json:"port"`
	Pw              string     `db:"pw" json:"pw"`
	UpdatedBy       *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate     *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	Cert          *TenantCert    `json:"cert"`
	Accreditation *Accreditation `json:"accreditation"`
}

// TableName sets the table name
func (AccreditationEpp) TableName() string {
	return "accreditation_epp"
}

// AccreditationTld
// tlds covered by an accreditation
type AccreditationTld struct {
	AccreditationId       string `db:"accreditation_id" json:"accreditation_id"`
	Id                    string `db:"id" json:"id"`
	IsDefault             bool   `db:"is_default" json:"is_default"`
	ProviderInstanceTldId string `db:"provider_instance_tld_id" json:"provider_instance_tld_id"`

	// belongs to
	Accreditation       *Accreditation       `json:"accreditation"`
	ProviderInstanceTld *ProviderInstanceTld `json:"provider_instance_tld"`

	// has many
	Domains                []Domain                `json:"domains"`
	OrderItemCreateDomains []OrderItemCreateDomain `json:"order_item_create_domains"`
	OrderItemRenewDomains  []OrderItemRenewDomain  `json:"order_item_renew_domains"`
	ProvisionDomains       []ProvisionDomain       `json:"provision_domains"`
}

// TableName sets the table name
func (AccreditationTld) TableName() string {
	return "accreditation_tld"
}

// Attribute

type Attribute struct {
	// A description of the attribute.
	Descr string `db:"descr" json:"descr"`
	// A SELECT query to filter the attribute''s value, like $$SELECT
	// alpha2 FROM country WHERE alpha2=trim('%s')$$.
	Filter *string `db:"filter" json:"filter"`
	Id     string  `db:"id" json:"id"`
	// The attributes's name.
	Name string `db:"name" json:"name"`
	// Reference to build a hierarchy of attributes.
	ParentId *string `db:"parent_id" json:"parent_id"`
	// The type of attribute from the attribute_type table
	TypeId string `db:"type_id" json:"type_id"`

	// belongs to
	Type *AttributeType `json:"type"`

	// has many
	Attributes        []Attribute        `json:"attributes"`
	ContactAttributes []ContactAttribute `json:"contact_attributes"`
}

// TableName sets the table name
func (Attribute) TableName() string {
	return "attribute"
}

// AttributeType

type AttributeType struct {
	CreatedBy   *string    `db:"created_by" json:"created_by"`
	CreatedDate *time.Time `db:"created_date" json:"created_date"`
	Descr       *string    `db:"descr" json:"descr"`
	Id          string     `db:"id" json:"id"`
	Name        string     `db:"name" json:"name"`
	UpdatedBy   *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate *time.Time `db:"updated_date" json:"updated_date"`

	// has many
	Attributes []Attribute `json:"attributes"`
}

// TableName sets the table name
func (AttributeType) TableName() string {
	return "attribute_type"
}

// AuditTrailLog
// Record of changes made to tables that inherit from _audit.
// Note: Only stored for relations that have an "id" primary index.
type AuditTrailLog struct {
	CreatedBy   *string   `db:"created_by" json:"created_by"`
	CreatedDate time.Time `db:"created_date" json:"created_date"`
	Id          int64     `db:"id" json:"id"`
	// Contain data encoded with `hstore`, representing the state of the
	// affected row after the `operation` was performed. This is stored
	// as simple text and must be converted back to `hstore` when data is
	// to be extracted within the database.
	NewValue *string `db:"new_value" json:"new_value"`
	ObjectId *string `db:"object_id" json:"object_id"`
	// Contain data encoded with `hstore`, representing the state of the
	// affected row before the `operation` was performed. This is stored
	// as simple text and must be converted back to `hstore` when data is
	// to be extracted within the database.
	OldValue *string `db:"old_value" json:"old_value"`
	// Stores the type of SQL operation performed and must be one of
	// `INSERT`, `TRUNCATE`, `UPDATE` or `DELETE`. Depending on the
	// actual value of this column, `old_value` and `new_value` might be
	// `NULL` (ie, there's no `new_value` for a `DELETE` operation).
	Operation     *string    `db:"operation" json:"operation"`
	StatementDate *time.Time `db:"statement_date" json:"statement_date"`
	// `type` stores the name of the table that was affected by the
	// current operation.
	TableName   string     `db:"table_name" json:"table_name"`
	UpdatedBy   *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate *time.Time `db:"updated_date" json:"updated_date"`
}

// TableName sets the table name
func (AuditTrailLog) TableName() string {
	return "audit_trail_log"
}

// AuditTrailLog_202303

type AuditTrailLog_202303 struct {
	CreatedBy     *string    `db:"created_by" json:"created_by"`
	CreatedDate   time.Time  `db:"created_date" json:"created_date"`
	Id            int64      `db:"id" json:"id"`
	NewValue      *string    `db:"new_value" json:"new_value"`
	ObjectId      *string    `db:"object_id" json:"object_id"`
	OldValue      *string    `db:"old_value" json:"old_value"`
	Operation     *string    `db:"operation" json:"operation"`
	StatementDate *time.Time `db:"statement_date" json:"statement_date"`
	TableName     string     `db:"table_name" json:"table_name"`
	UpdatedBy     *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate   *time.Time `db:"updated_date" json:"updated_date"`
}

// TableName sets the table name
func (AuditTrailLog_202303) TableName() string {
	return "audit_trail_log_202303"
}

// AuditTrailLog_202304

type AuditTrailLog_202304 struct {
	CreatedBy     *string    `db:"created_by" json:"created_by"`
	CreatedDate   time.Time  `db:"created_date" json:"created_date"`
	Id            int64      `db:"id" json:"id"`
	NewValue      *string    `db:"new_value" json:"new_value"`
	ObjectId      *string    `db:"object_id" json:"object_id"`
	OldValue      *string    `db:"old_value" json:"old_value"`
	Operation     *string    `db:"operation" json:"operation"`
	StatementDate *time.Time `db:"statement_date" json:"statement_date"`
	TableName     string     `db:"table_name" json:"table_name"`
	UpdatedBy     *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate   *time.Time `db:"updated_date" json:"updated_date"`
}

// TableName sets the table name
func (AuditTrailLog_202304) TableName() string {
	return "audit_trail_log_202304"
}

// BusinessEntity

type BusinessEntity struct {
	CreatedBy   *string    `db:"created_by" json:"created_by"`
	CreatedDate *time.Time `db:"created_date" json:"created_date"`
	DeletedBy   *string    `db:"deleted_by" json:"deleted_by"`
	DeletedDate *time.Time `db:"deleted_date" json:"deleted_date"`
	Descr       string     `db:"descr" json:"descr"`
	Id          string     `db:"id" json:"id"`
	Name        string     `db:"name" json:"name"`
	UpdatedBy   *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate *time.Time `db:"updated_date" json:"updated_date"`

	// has many
	Customers []Customer `json:"customers"`
	Providers []Provider `json:"providers"`
	Registrys []Registry `json:"registrys"`
	Tenants   []Tenant   `json:"tenants"`
}

// TableName sets the table name
func (BusinessEntity) TableName() string {
	return "business_entity"
}

// CertificateAuthority

type CertificateAuthority struct {
	Cert         *string    `db:"cert" json:"cert"`
	CreatedBy    *string    `db:"created_by" json:"created_by"`
	CreatedDate  *time.Time `db:"created_date" json:"created_date"`
	Descr        *string    `db:"descr" json:"descr"`
	Id           string     `db:"id" json:"id"`
	Name         string     `db:"name" json:"name"`
	ServiceRange string     `db:"service_range" json:"service_range"`
	UpdatedBy    *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate  *time.Time `db:"updated_date" json:"updated_date"`

	// has many
	TenantCerts []TenantCert `json:"tenant_certs"`
}

// TableName sets the table name
func (CertificateAuthority) TableName() string {
	return "certificate_authority"
}

// Contact
// Contains the basic not character set dependent attributes of extensible
// contacts.
type Contact struct {
	Country            string         `db:"country" json:"country"`
	CreatedBy          *string        `db:"created_by" json:"created_by"`
	CreatedDate        *time.Time     `db:"created_date" json:"created_date"`
	CustomerContactRef *string        `db:"customer_contact_ref" json:"customer_contact_ref"`
	DeletedBy          *string        `db:"deleted_by" json:"deleted_by"`
	DeletedDate        *time.Time     `db:"deleted_date" json:"deleted_date"`
	Documentation      pq.StringArray `db:"documentation" json:"documentation"`
	Email              *string        `db:"email" json:"email"`
	Fax                *string        `db:"fax" json:"fax"`
	Id                 string         `db:"id" json:"id"`
	Language           *string        `db:"language" json:"language"`
	OrgDuns            *string        `db:"org_duns" json:"org_duns"`
	OrgReg             *string        `db:"org_reg" json:"org_reg"`
	OrgVat             *string        `db:"org_vat" json:"org_vat"`
	Phone              *string        `db:"phone" json:"phone"`
	Tags               pq.StringArray `db:"tags" json:"tags"`
	TenantCustomerId   *string        `db:"tenant_customer_id" json:"tenant_customer_id"`
	Title              *string        `db:"title" json:"title"`
	TypeId             string         `db:"type_id" json:"type_id"`
	UpdatedBy          *string        `db:"updated_by" json:"updated_by"`
	UpdatedDate        *time.Time     `db:"updated_date" json:"updated_date"`

	// belongs to
	CountryObj     *Country        `json:"country_obj"`
	LanguageObj    *Language       `json:"language_obj"`
	TenantCustomer *TenantCustomer `json:"tenant_customer"`
	Type           *ContactType    `json:"type"`

	// has many
	ContactAttributes       []ContactAttribute       `json:"contact_attributes"`
	ContactPostals          []ContactPostal          `json:"contact_postals"`
	DomainContacts          []DomainContact          `json:"domain_contacts"`
	ProvisionContacts       []ProvisionContact       `json:"provision_contacts"`
	ProvisionDomainContacts []ProvisionDomainContact `json:"provision_domain_contacts"`
}

// TableName sets the table name
func (Contact) TableName() string {
	return "contact"
}

// ContactAttribute

type ContactAttribute struct {
	AttributeId     string     `db:"attribute_id" json:"attribute_id"`
	AttributeTypeId string     `db:"attribute_type_id" json:"attribute_type_id"`
	ContactId       string     `db:"contact_id" json:"contact_id"`
	CreatedBy       *string    `db:"created_by" json:"created_by"`
	CreatedDate     *time.Time `db:"created_date" json:"created_date"`
	DeletedBy       *string    `db:"deleted_by" json:"deleted_by"`
	DeletedDate     *time.Time `db:"deleted_date" json:"deleted_date"`
	Id              string     `db:"id" json:"id"`
	UpdatedBy       *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate     *time.Time `db:"updated_date" json:"updated_date"`
	Value           string     `db:"value" json:"value"`

	// belongs to
	Contact       *Contact   `json:"contact"`
	Attribute     *Attribute `json:"attribute"`
	AttributeType *Attribute `json:"attribute_type"`
}

// TableName sets the table name
func (ContactAttribute) TableName() string {
	return "contact_attribute"
}

// ContactPostal
// Contains the character set dependent attributes of extensible contacts.
type ContactPostal struct {
	Address1        string     `db:"address1" json:"address1"`
	Address2        *string    `db:"address2" json:"address2"`
	Address3        *string    `db:"address3" json:"address3"`
	City            string     `db:"city" json:"city"`
	ContactId       string     `db:"contact_id" json:"contact_id"`
	CreatedBy       *string    `db:"created_by" json:"created_by"`
	CreatedDate     *time.Time `db:"created_date" json:"created_date"`
	DeletedBy       *string    `db:"deleted_by" json:"deleted_by"`
	DeletedDate     *time.Time `db:"deleted_date" json:"deleted_date"`
	FirstName       *string    `db:"first_name" json:"first_name"`
	Id              string     `db:"id" json:"id"`
	IsInternational bool       `db:"is_international" json:"is_international"`
	LastName        *string    `db:"last_name" json:"last_name"`
	OrgName         *string    `db:"org_name" json:"org_name"`
	PostalCode      *string    `db:"postal_code" json:"postal_code"`
	State           *string    `db:"state" json:"state"`
	UpdatedBy       *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate     *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	Contact *Contact `json:"contact"`
}

// TableName sets the table name
func (ContactPostal) TableName() string {
	return "contact_postal"
}

// ContactType

type ContactType struct {
	Descr *string `db:"descr" json:"descr"`
	Id    string  `db:"id" json:"id"`
	Name  string  `db:"name" json:"name"`

	// has many
	Contacts []Contact `json:"contacts"`
}

// TableName sets the table name
func (ContactType) TableName() string {
	return "contact_type"
}

// Country

type Country struct {
	// The ISO 3166-1 two letter country code, see
	// https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2.
	Alpha2 string `db:"alpha2" json:"alpha2"`
	// The ISO 3166-1 three letter country code, see
	// https://en.wikipedia.org/wiki/ISO_3166-1_alpha-3.
	Alpha3 string `db:"alpha3" json:"alpha3"`
	// The country's calling code accord, see
	// https://en.wikipedia.org/wiki/List_of_country_calling_codes.
	CallingCode *string `db:"calling_code" json:"calling_code"`
	Id          string  `db:"id" json:"id"`
	// The country's name.
	Name string `db:"name" json:"name"`

	// has many
	Contacts []Contact `json:"contacts"`
}

// TableName sets the table name
func (Country) TableName() string {
	return "country"
}

// CreateContactPlan

type CreateContactPlan struct {
	CreatedBy         *string        `db:"created_by" json:"created_by"`
	CreatedDate       *time.Time     `db:"created_date" json:"created_date"`
	Id                string         `db:"id" json:"id"`
	OrderItemId       string         `db:"order_item_id" json:"order_item_id"`
	OrderItemObjectId string         `db:"order_item_object_id" json:"order_item_object_id"`
	ParentId          *string        `db:"parent_id" json:"parent_id"`
	ReferenceId       *string        `db:"reference_id" json:"reference_id"`
	ResultData        types.JSONText `db:"result_data" json:"result_data"`
	ResultMessage     *string        `db:"result_message" json:"result_message"`
	StatusId          string         `db:"status_id" json:"status_id"`
	UpdatedBy         *string        `db:"updated_by" json:"updated_by"`
	UpdatedDate       *time.Time     `db:"updated_date" json:"updated_date"`

	// belongs to
	OrderItem *OrderItemCreateContact `json:"order_item"`
}

// TableName sets the table name
func (CreateContactPlan) TableName() string {
	return "create_contact_plan"
}

// CreateDomainContact
// contains the association of contacts and domains at order time
type CreateDomainContact struct {
	CreateDomainId      string     `db:"create_domain_id" json:"create_domain_id"`
	CreatedBy           *string    `db:"created_by" json:"created_by"`
	CreatedDate         *time.Time `db:"created_date" json:"created_date"`
	DomainContactTypeId string     `db:"domain_contact_type_id" json:"domain_contact_type_id"`
	Id                  string     `db:"id" json:"id"`
	// since the order_contact table inherits from the contact table, the
	// data will be available in the contact, this also allow for contact
	// reutilization
	OrderContactId *string    `db:"order_contact_id" json:"order_contact_id"`
	UpdatedBy      *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate    *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	DomainContactType *DomainContactType     `json:"domain_contact_type"`
	OrderContact      *OrderContact          `json:"order_contact"`
	CreateDomain      *OrderItemCreateDomain `json:"create_domain"`
}

// TableName sets the table name
func (CreateDomainContact) TableName() string {
	return "create_domain_contact"
}

// CreateDomainNameserver

type CreateDomainNameserver struct {
	CreateDomainId string     `db:"create_domain_id" json:"create_domain_id"`
	CreatedBy      *string    `db:"created_by" json:"created_by"`
	CreatedDate    *time.Time `db:"created_date" json:"created_date"`
	Id             string     `db:"id" json:"id"`
	Name           string     `db:"name" json:"name"`
	UpdatedBy      *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate    *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	CreateDomain *OrderItemCreateDomain `json:"create_domain"`

	// has many
	CreateDomainNameserverAddrs []CreateDomainNameserverAddr `json:"create_domain_nameserver_addrs"`
}

// TableName sets the table name
func (CreateDomainNameserver) TableName() string {
	return "create_domain_nameserver"
}

// CreateDomainNameserverAddr

type CreateDomainNameserverAddr struct {
	Addr         string     `db:"addr" json:"addr"`
	CreatedBy    *string    `db:"created_by" json:"created_by"`
	CreatedDate  *time.Time `db:"created_date" json:"created_date"`
	Id           string     `db:"id" json:"id"`
	NameserverId string     `db:"nameserver_id" json:"nameserver_id"`
	UpdatedBy    *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate  *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	Nameserver *CreateDomainNameserver `json:"nameserver"`
}

// TableName sets the table name
func (CreateDomainNameserverAddr) TableName() string {
	return "create_domain_nameserver_addr"
}

// CreateDomainPlan

type CreateDomainPlan struct {
	CreatedBy         *string        `db:"created_by" json:"created_by"`
	CreatedDate       *time.Time     `db:"created_date" json:"created_date"`
	Id                string         `db:"id" json:"id"`
	OrderItemId       string         `db:"order_item_id" json:"order_item_id"`
	OrderItemObjectId string         `db:"order_item_object_id" json:"order_item_object_id"`
	ParentId          *string        `db:"parent_id" json:"parent_id"`
	ReferenceId       *string        `db:"reference_id" json:"reference_id"`
	ResultData        types.JSONText `db:"result_data" json:"result_data"`
	ResultMessage     *string        `db:"result_message" json:"result_message"`
	StatusId          string         `db:"status_id" json:"status_id"`
	UpdatedBy         *string        `db:"updated_by" json:"updated_by"`
	UpdatedDate       *time.Time     `db:"updated_date" json:"updated_date"`

	// belongs to
	OrderItem *OrderItemCreateDomain `json:"order_item"`
}

// TableName sets the table name
func (CreateDomainPlan) TableName() string {
	return "create_domain_plan"
}

// Customer

type Customer struct {
	BusinessEntityId string     `db:"business_entity_id" json:"business_entity_id"`
	CreatedBy        *string    `db:"created_by" json:"created_by"`
	CreatedDate      *time.Time `db:"created_date" json:"created_date"`
	DeletedBy        *string    `db:"deleted_by" json:"deleted_by"`
	DeletedDate      *time.Time `db:"deleted_date" json:"deleted_date"`
	Descr            *string    `db:"descr" json:"descr"`
	Id               string     `db:"id" json:"id"`
	Name             string     `db:"name" json:"name"`
	ParentCustomerId *string    `db:"parent_customer_id" json:"parent_customer_id"`
	UpdatedBy        *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate      *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	BusinessEntity *BusinessEntity `json:"business_entity"`

	// has many
	Customers       []Customer       `json:"customers"`
	CustomerUsers   []CustomerUser   `json:"customer_users"`
	TenantCustomers []TenantCustomer `json:"tenant_customers"`
}

// TableName sets the table name
func (Customer) TableName() string {
	return "customer"
}

// CustomerUser

type CustomerUser struct {
	CreatedBy   *string    `db:"created_by" json:"created_by"`
	CreatedDate *time.Time `db:"created_date" json:"created_date"`
	CustomerId  string     `db:"customer_id" json:"customer_id"`
	DeletedBy   *string    `db:"deleted_by" json:"deleted_by"`
	DeletedDate *time.Time `db:"deleted_date" json:"deleted_date"`
	Id          string     `db:"id" json:"id"`
	UpdatedBy   *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate *time.Time `db:"updated_date" json:"updated_date"`
	UserId      string     `db:"user_id" json:"user_id"`

	// belongs to
	User     *User     `json:"user"`
	Customer *Customer `json:"customer"`

	// has many
	Orders []Order `json:"orders"`
}

// TableName sets the table name
func (CustomerUser) TableName() string {
	return "customer_user"
}

// Domain

type Domain struct {
	AccreditationTldId string     `db:"accreditation_tld_id" json:"accreditation_tld_id"`
	AuthInfo           *string    `db:"auth_info" json:"auth_info"`
	CreatedBy          *string    `db:"created_by" json:"created_by"`
	CreatedDate        *time.Time `db:"created_date" json:"created_date"`
	ExpiryDate         time.Time  `db:"expiry_date" json:"expiry_date"`
	Id                 string     `db:"id" json:"id"`
	Name               string     `db:"name" json:"name"`
	Roid               *string    `db:"roid" json:"roid"`
	RyCreatedDate      time.Time  `db:"ry_created_date" json:"ry_created_date"`
	RyExpiryDate       time.Time  `db:"ry_expiry_date" json:"ry_expiry_date"`
	RyTransferedDate   *time.Time `db:"ry_transfered_date" json:"ry_transfered_date"`
	RyUpdatedDate      *time.Time `db:"ry_updated_date" json:"ry_updated_date"`
	TenantCustomerId   string     `db:"tenant_customer_id" json:"tenant_customer_id"`
	UpdatedBy          *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate        *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	AccreditationTld *AccreditationTld `json:"accreditation_tld"`
	TenantCustomer   *TenantCustomer   `json:"tenant_customer"`

	// has many
	DomainContacts        []DomainContact        `json:"domain_contacts"`
	DomainHosts           []DomainHost           `json:"domain_hosts"`
	Hosts                 []Host                 `json:"hosts"`
	ProvisionDomainRenews []ProvisionDomainRenew `json:"provision_domain_renews"`
}

// TableName sets the table name
func (Domain) TableName() string {
	return "domain"
}

// DomainContact

type DomainContact struct {
	ContactId           string     `db:"contact_id" json:"contact_id"`
	CreatedBy           *string    `db:"created_by" json:"created_by"`
	CreatedDate         *time.Time `db:"created_date" json:"created_date"`
	DomainContactTypeId string     `db:"domain_contact_type_id" json:"domain_contact_type_id"`
	DomainId            string     `db:"domain_id" json:"domain_id"`
	Id                  string     `db:"id" json:"id"`
	IsLocalPresence     bool       `db:"is_local_presence" json:"is_local_presence"`
	IsPrivacyProxy      bool       `db:"is_privacy_proxy" json:"is_privacy_proxy"`
	UpdatedBy           *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate         *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	DomainContactType *DomainContactType `json:"domain_contact_type"`
	Domain            *Domain            `json:"domain"`
	Contact           *Contact           `json:"contact"`
}

// TableName sets the table name
func (DomainContact) TableName() string {
	return "domain_contact"
}

// DomainContactType

type DomainContactType struct {
	Descr *string `db:"descr" json:"descr"`
	Id    string  `db:"id" json:"id"`
	Name  string  `db:"name" json:"name"`

	// has many
	CreateDomainContacts    []CreateDomainContact    `json:"create_domain_contacts"`
	DomainContacts          []DomainContact          `json:"domain_contacts"`
	ProvisionDomainContacts []ProvisionDomainContact `json:"provision_domain_contacts"`
}

// TableName sets the table name
func (DomainContactType) TableName() string {
	return "domain_contact_type"
}

// DomainHost

type DomainHost struct {
	CreatedBy   *string    `db:"created_by" json:"created_by"`
	CreatedDate *time.Time `db:"created_date" json:"created_date"`
	DomainId    string     `db:"domain_id" json:"domain_id"`
	HostId      string     `db:"host_id" json:"host_id"`
	Id          string     `db:"id" json:"id"`
	UpdatedBy   *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	Domain *Domain `json:"domain"`
	Host   *Host   `json:"host"`
}

// TableName sets the table name
func (DomainHost) TableName() string {
	return "domain_host"
}

// EppExtension

type EppExtension struct {
	CreatedBy     *string    `db:"created_by" json:"created_by"`
	CreatedDate   *time.Time `db:"created_date" json:"created_date"`
	Decr          *string    `db:"decr" json:"decr"`
	DocUrl        *string    `db:"doc_url" json:"doc_url"`
	Id            string     `db:"id" json:"id"`
	IsImplemented bool       `db:"is_implemented" json:"is_implemented"`
	Name          string     `db:"name" json:"name"`
	UpdatedBy     *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate   *time.Time `db:"updated_date" json:"updated_date"`

	// has many
	ProviderInstanceEppExts []ProviderInstanceEppExt `json:"provider_instance_epp_exts"`
}

// TableName sets the table name
func (EppExtension) TableName() string {
	return "epp_extension"
}

// ErrorCategory

type ErrorCategory struct {
	Descr *string `db:"descr" json:"descr"`
	Id    string  `db:"id" json:"id"`
	Name  string  `db:"name" json:"name"`

	// has many
	ErrorDictionarys []ErrorDictionary `json:"error_dictionarys"`
}

// TableName sets the table name
func (ErrorCategory) TableName() string {
	return "error_category"
}

// ErrorDictionary
// This table contains the description for all error messages that can be
// generated by the system. It is directly used used by database functions to
// `RAISE EXCEPTION` when required.
type ErrorDictionary struct {
	CategoryId      string         `db:"category_id" json:"category_id"`
	ColumnsAffected pq.StringArray `db:"columns_affected" json:"columns_affected"`
	Id              int            `db:"id" json:"id"`
	Message         string         `db:"message" json:"message"`

	// belongs to
	Category *ErrorCategory `json:"category"`
}

// TableName sets the table name
func (ErrorDictionary) TableName() string {
	return "error_dictionary"
}

// Host
// host objects
type Host struct {
	CreatedBy   *string    `db:"created_by" json:"created_by"`
	CreatedDate *time.Time `db:"created_date" json:"created_date"`
	// if the host is a sub domain of a registered name, we will add the
	// reference here.
	DomainId         *string    `db:"domain_id" json:"domain_id"`
	Id               string     `db:"id" json:"id"`
	Name             string     `db:"name" json:"name"`
	TenantCustomerId string     `db:"tenant_customer_id" json:"tenant_customer_id"`
	UpdatedBy        *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate      *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	Domain         *Domain         `json:"domain"`
	TenantCustomer *TenantCustomer `json:"tenant_customer"`

	// has many
	DomainHosts          []DomainHost          `json:"domain_hosts"`
	HostAddrs            []HostAddr            `json:"host_addrs"`
	ProvisionDomainHosts []ProvisionDomainHost `json:"provision_domain_hosts"`
	ProvisionHosts       []ProvisionHost       `json:"provision_hosts"`
}

// TableName sets the table name
func (Host) TableName() string {
	return "host"
}

// HostAddr

type HostAddr struct {
	Address     *string    `db:"address" json:"address"`
	CreatedBy   *string    `db:"created_by" json:"created_by"`
	CreatedDate *time.Time `db:"created_date" json:"created_date"`
	HostId      string     `db:"host_id" json:"host_id"`
	Id          string     `db:"id" json:"id"`
	UpdatedBy   *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	Host *Host `json:"host"`
}

// TableName sets the table name
func (HostAddr) TableName() string {
	return "host_addr"
}

// Job

type Job struct {
	CreatedBy        string         `db:"created_by" json:"created_by"`
	CreatedDate      time.Time      `db:"created_date" json:"created_date"`
	Data             types.JSONText `db:"data" json:"data"`
	EndDate          *time.Time     `db:"end_date" json:"end_date"`
	EventId          *string        `db:"event_id" json:"event_id"`
	Id               string         `db:"id" json:"id"`
	ReferenceId      *string        `db:"reference_id" json:"reference_id"`
	ResultData       types.JSONText `db:"result_data" json:"result_data"`
	ResultMsg        *string        `db:"result_msg" json:"result_msg"`
	RetryCount       *int           `db:"retry_count" json:"retry_count"`
	RetryDate        *time.Time     `db:"retry_date" json:"retry_date"`
	StartDate        *time.Time     `db:"start_date" json:"start_date"`
	StatusId         string         `db:"status_id" json:"status_id"`
	TenantCustomerId *string        `db:"tenant_customer_id" json:"tenant_customer_id"`
	TypeId           string         `db:"type_id" json:"type_id"`
	UpdatedBy        *string        `db:"updated_by" json:"updated_by"`
	UpdatedDate      *time.Time     `db:"updated_date" json:"updated_date"`

	// belongs to
	Type           *JobType        `json:"type"`
	TenantCustomer *TenantCustomer `json:"tenant_customer"`
	Status         *JobStatus      `json:"status"`
}

// TableName sets the table name
func (Job) TableName() string {
	return "job"
}

// JobStatus

type JobStatus struct {
	Descr     string `db:"descr" json:"descr"`
	Id        string `db:"id" json:"id"`
	IsFinal   bool   `db:"is_final" json:"is_final"`
	IsSuccess bool   `db:"is_success" json:"is_success"`
	Name      string `db:"name" json:"name"`

	// has many
	Jobs []Job `json:"jobs"`
}

// TableName sets the table name
func (JobStatus) TableName() string {
	return "job_status"
}

// JobType

type JobType struct {
	Descr                 string  `db:"descr" json:"descr"`
	Id                    string  `db:"id" json:"id"`
	Name                  string  `db:"name" json:"name"`
	ReferenceStatusColumn string  `db:"reference_status_column" json:"reference_status_column"`
	ReferenceStatusTable  *string `db:"reference_status_table" json:"reference_status_table"`
	ReferenceTable        *string `db:"reference_table" json:"reference_table"`
	RoutingKey            *string `db:"routing_key" json:"routing_key"`

	// has many
	Jobs []Job `json:"jobs"`
}

// TableName sets the table name
func (JobType) TableName() string {
	return "job_type"
}

// Language

type Language struct {
	// The ISO 639-1 two letter language code, see
	// https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes.
	Alpha2 string `db:"alpha2" json:"alpha2"`
	// The ISO 639-2/B three letter language code, see
	// https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes.
	Alpha3b string `db:"alpha3b" json:"alpha3b"`
	// The ISO 639-2/T three letter language code, see
	// https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes.
	Alpha3t string `db:"alpha3t" json:"alpha3t"`
	Id      string `db:"id" json:"id"`
	// The language's name.
	Name string `db:"name" json:"name"`

	// has many
	Contacts []Contact `json:"contacts"`
}

// TableName sets the table name
func (Language) TableName() string {
	return "language"
}

// Migration
// Record of schema migrations applied.
type Migration struct {
	// Postgres timestamp when migration was recorded.
	AppliedDate time.Time `db:"applied_date" json:"applied_date"`
	// Name of migration from migration filename.
	Name string `db:"name" json:"name"`
	// Timestamp string of migration file in format YYYYMMDDHHMMSS (must
	// match filename).
	Version string `db:"version" json:"version"`
}

// TableName sets the table name
func (Migration) TableName() string {
	return "migration"
}

// Order

type Order struct {
	CreatedBy        *string    `db:"created_by" json:"created_by"`
	CreatedDate      *time.Time `db:"created_date" json:"created_date"`
	CustomerUserId   *string    `db:"customer_user_id" json:"customer_user_id"`
	Id               string     `db:"id" json:"id"`
	PathId           string     `db:"path_id" json:"path_id"`
	StatusId         string     `db:"status_id" json:"status_id"`
	TenantCustomerId string     `db:"tenant_customer_id" json:"tenant_customer_id"`
	TypeId           string     `db:"type_id" json:"type_id"`
	UpdatedBy        *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate      *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	Status         *OrderStatus     `json:"status"`
	Path           *OrderStatusPath `json:"path"`
	Type           *OrderType       `json:"type"`
	CustomerUser   *CustomerUser    `json:"customer_user"`
	TenantCustomer *TenantCustomer  `json:"tenant_customer"`

	// has many
	OrderContacts           []OrderContact           `json:"order_contacts"`
	OrderItems              []OrderItem              `json:"order_items"`
	OrderItemCreateContacts []OrderItemCreateContact `json:"order_item_create_contacts"`
	OrderItemCreateDomains  []OrderItemCreateDomain  `json:"order_item_create_domains"`
	OrderItemRenewDomains   []OrderItemRenewDomain   `json:"order_item_renew_domains"`
}

// TableName sets the table name
func (Order) TableName() string {
	return "order"
}

// OrderContact
// will be dropped in favour of order_item_create_contact
type OrderContact struct {
	Country            string         `db:"country" json:"country"`
	CreatedBy          *string        `db:"created_by" json:"created_by"`
	CreatedDate        *time.Time     `db:"created_date" json:"created_date"`
	CustomerContactRef *string        `db:"customer_contact_ref" json:"customer_contact_ref"`
	DeletedBy          *string        `db:"deleted_by" json:"deleted_by"`
	DeletedDate        *time.Time     `db:"deleted_date" json:"deleted_date"`
	Documentation      pq.StringArray `db:"documentation" json:"documentation"`
	Email              *string        `db:"email" json:"email"`
	Fax                *string        `db:"fax" json:"fax"`
	Id                 string         `db:"id" json:"id"`
	Language           *string        `db:"language" json:"language"`
	OrderId            string         `db:"order_id" json:"order_id"`
	OrgDuns            *string        `db:"org_duns" json:"org_duns"`
	OrgReg             *string        `db:"org_reg" json:"org_reg"`
	OrgVat             *string        `db:"org_vat" json:"org_vat"`
	Phone              *string        `db:"phone" json:"phone"`
	Tags               pq.StringArray `db:"tags" json:"tags"`
	TenantCustomerId   *string        `db:"tenant_customer_id" json:"tenant_customer_id"`
	Title              *string        `db:"title" json:"title"`
	TypeId             string         `db:"type_id" json:"type_id"`
	UpdatedBy          *string        `db:"updated_by" json:"updated_by"`
	UpdatedDate        *time.Time     `db:"updated_date" json:"updated_date"`

	// belongs to
	Order *Order `json:"order"`

	// has many
	CreateDomainContacts []CreateDomainContact `json:"create_domain_contacts"`
	OrderContactPostals  []OrderContactPostal  `json:"order_contact_postals"`
}

// TableName sets the table name
func (OrderContact) TableName() string {
	return "order_contact"
}

// OrderContactPostal
// will be dropped in favour of order_item_create_contact_postal
type OrderContactPostal struct {
	Address1        string     `db:"address1" json:"address1"`
	Address2        *string    `db:"address2" json:"address2"`
	Address3        *string    `db:"address3" json:"address3"`
	City            string     `db:"city" json:"city"`
	ContactId       string     `db:"contact_id" json:"contact_id"`
	CreatedBy       *string    `db:"created_by" json:"created_by"`
	CreatedDate     *time.Time `db:"created_date" json:"created_date"`
	DeletedBy       *string    `db:"deleted_by" json:"deleted_by"`
	DeletedDate     *time.Time `db:"deleted_date" json:"deleted_date"`
	FirstName       *string    `db:"first_name" json:"first_name"`
	Id              string     `db:"id" json:"id"`
	IsInternational bool       `db:"is_international" json:"is_international"`
	LastName        *string    `db:"last_name" json:"last_name"`
	OrgName         *string    `db:"org_name" json:"org_name"`
	PostalCode      *string    `db:"postal_code" json:"postal_code"`
	State           *string    `db:"state" json:"state"`
	UpdatedBy       *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate     *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	Contact *OrderContact `json:"contact"`
}

// TableName sets the table name
func (OrderContactPostal) TableName() string {
	return "order_contact_postal"
}

// OrderItem

type OrderItem struct {
	CreatedBy         *string    `db:"created_by" json:"created_by"`
	CreatedDate       *time.Time `db:"created_date" json:"created_date"`
	Id                string     `db:"id" json:"id"`
	OrderId           string     `db:"order_id" json:"order_id"`
	ParentOrderItemId *string    `db:"parent_order_item_id" json:"parent_order_item_id"`
	StatusId          string     `db:"status_id" json:"status_id"`
	UpdatedBy         *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate       *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	Status *OrderItemStatus `json:"status"`
	Order  *Order           `json:"order"`

	// has many
	OrderItems []OrderItem `json:"order_items"`
}

// TableName sets the table name
func (OrderItem) TableName() string {
	return "order_item"
}

// OrderItemCreateContact

type OrderItemCreateContact struct {
	Country            string         `db:"country" json:"country"`
	CreatedBy          *string        `db:"created_by" json:"created_by"`
	CreatedDate        *time.Time     `db:"created_date" json:"created_date"`
	CustomerContactRef *string        `db:"customer_contact_ref" json:"customer_contact_ref"`
	DeletedBy          *string        `db:"deleted_by" json:"deleted_by"`
	DeletedDate        *time.Time     `db:"deleted_date" json:"deleted_date"`
	Documentation      pq.StringArray `db:"documentation" json:"documentation"`
	Email              *string        `db:"email" json:"email"`
	Fax                *string        `db:"fax" json:"fax"`
	Id                 string         `db:"id" json:"id"`
	Language           *string        `db:"language" json:"language"`
	OrderId            string         `db:"order_id" json:"order_id"`
	OrgDuns            *string        `db:"org_duns" json:"org_duns"`
	OrgReg             *string        `db:"org_reg" json:"org_reg"`
	OrgVat             *string        `db:"org_vat" json:"org_vat"`
	ParentOrderItemId  *string        `db:"parent_order_item_id" json:"parent_order_item_id"`
	Phone              *string        `db:"phone" json:"phone"`
	StatusId           string         `db:"status_id" json:"status_id"`
	Tags               pq.StringArray `db:"tags" json:"tags"`
	TenantCustomerId   *string        `db:"tenant_customer_id" json:"tenant_customer_id"`
	Title              *string        `db:"title" json:"title"`
	TypeId             string         `db:"type_id" json:"type_id"`
	UpdatedBy          *string        `db:"updated_by" json:"updated_by"`
	UpdatedDate        *time.Time     `db:"updated_date" json:"updated_date"`

	// belongs to
	Order  *Order           `json:"order"`
	Status *OrderItemStatus `json:"status"`

	// has many
	CreateContactPlans               []CreateContactPlan               `json:"create_contact_plans"`
	OrderItemCreateContactAttributes []OrderItemCreateContactAttribute `json:"order_item_create_contact_attributes"`
	OrderItemCreateContactPostals    []OrderItemCreateContactPostal    `json:"order_item_create_contact_postals"`
}

// TableName sets the table name
func (OrderItemCreateContact) TableName() string {
	return "order_item_create_contact"
}

// OrderItemCreateContactAttribute

type OrderItemCreateContactAttribute struct {
	AttributeId     string     `db:"attribute_id" json:"attribute_id"`
	AttributeTypeId string     `db:"attribute_type_id" json:"attribute_type_id"`
	ContactId       string     `db:"contact_id" json:"contact_id"`
	CreatedBy       *string    `db:"created_by" json:"created_by"`
	CreatedDate     *time.Time `db:"created_date" json:"created_date"`
	DeletedBy       *string    `db:"deleted_by" json:"deleted_by"`
	DeletedDate     *time.Time `db:"deleted_date" json:"deleted_date"`
	Id              string     `db:"id" json:"id"`
	UpdatedBy       *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate     *time.Time `db:"updated_date" json:"updated_date"`
	Value           string     `db:"value" json:"value"`

	// belongs to
	Contact *OrderItemCreateContact `json:"contact"`
}

// TableName sets the table name
func (OrderItemCreateContactAttribute) TableName() string {
	return "order_item_create_contact_attribute"
}

// OrderItemCreateContactPostal

type OrderItemCreateContactPostal struct {
	Address1        string     `db:"address1" json:"address1"`
	Address2        *string    `db:"address2" json:"address2"`
	Address3        *string    `db:"address3" json:"address3"`
	City            string     `db:"city" json:"city"`
	ContactId       string     `db:"contact_id" json:"contact_id"`
	CreatedBy       *string    `db:"created_by" json:"created_by"`
	CreatedDate     *time.Time `db:"created_date" json:"created_date"`
	DeletedBy       *string    `db:"deleted_by" json:"deleted_by"`
	DeletedDate     *time.Time `db:"deleted_date" json:"deleted_date"`
	FirstName       *string    `db:"first_name" json:"first_name"`
	Id              string     `db:"id" json:"id"`
	IsInternational bool       `db:"is_international" json:"is_international"`
	LastName        *string    `db:"last_name" json:"last_name"`
	OrgName         *string    `db:"org_name" json:"org_name"`
	PostalCode      *string    `db:"postal_code" json:"postal_code"`
	State           *string    `db:"state" json:"state"`
	UpdatedBy       *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate     *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	Contact *OrderItemCreateContact `json:"contact"`
}

// TableName sets the table name
func (OrderItemCreateContactPostal) TableName() string {
	return "order_item_create_contact_postal"
}

// OrderItemCreateDomain

type OrderItemCreateDomain struct {
	AccreditationTldId string     `db:"accreditation_tld_id" json:"accreditation_tld_id"`
	CreatedBy          *string    `db:"created_by" json:"created_by"`
	CreatedDate        *time.Time `db:"created_date" json:"created_date"`
	Id                 string     `db:"id" json:"id"`
	Name               string     `db:"name" json:"name"`
	OrderId            string     `db:"order_id" json:"order_id"`
	ParentOrderItemId  *string    `db:"parent_order_item_id" json:"parent_order_item_id"`
	RegistrationPeriod int        `db:"registration_period" json:"registration_period"`
	StatusId           string     `db:"status_id" json:"status_id"`
	UpdatedBy          *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate        *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	AccreditationTld *AccreditationTld `json:"accreditation_tld"`
	Order            *Order            `json:"order"`
	Status           *OrderItemStatus  `json:"status"`

	// has many
	CreateDomainContacts    []CreateDomainContact    `json:"create_domain_contacts"`
	CreateDomainNameservers []CreateDomainNameserver `json:"create_domain_nameservers"`
	CreateDomainPlans       []CreateDomainPlan       `json:"create_domain_plans"`
}

// TableName sets the table name
func (OrderItemCreateDomain) TableName() string {
	return "order_item_create_domain"
}

// OrderItemObject

type OrderItemObject struct {
	CreatedBy   *string    `db:"created_by" json:"created_by"`
	CreatedDate *time.Time `db:"created_date" json:"created_date"`
	Descr       *string    `db:"descr" json:"descr"`
	Id          string     `db:"id" json:"id"`
	Name        string     `db:"name" json:"name"`
	UpdatedBy   *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate *time.Time `db:"updated_date" json:"updated_date"`

	// has many
	OrderItemPlans     []OrderItemPlan     `json:"order_item_plans"`
	OrderItemStrategys []OrderItemStrategy `json:"order_item_strategys"`
}

// TableName sets the table name
func (OrderItemObject) TableName() string {
	return "order_item_object"
}

// OrderItemPlan
// stores the plan on how an order must be provisioned
type OrderItemPlan struct {
	Id                string  `db:"id" json:"id"`
	OrderItemId       string  `db:"order_item_id" json:"order_item_id"`
	OrderItemObjectId string  `db:"order_item_object_id" json:"order_item_object_id"`
	ParentId          *string `db:"parent_id" json:"parent_id"`
	// since a foreign key would depend on the `order_item_object_id`
	// type, to simplify the setup the reference_id is used to
	// conditionally point to rows in the `create_domain_*` tables
	ReferenceId   *string        `db:"reference_id" json:"reference_id"`
	ResultData    types.JSONText `db:"result_data" json:"result_data"`
	ResultMessage *string        `db:"result_message" json:"result_message"`
	StatusId      string         `db:"status_id" json:"status_id"`

	// belongs to
	Status          *OrderItemPlanStatus `json:"status"`
	OrderItemObject *OrderItemObject     `json:"order_item_object"`

	// has many
	OrderItemPlans []OrderItemPlan `json:"order_item_plans"`
}

// TableName sets the table name
func (OrderItemPlan) TableName() string {
	return "order_item_plan"
}

// OrderItemPlanStatus

type OrderItemPlanStatus struct {
	CreatedBy   *string    `db:"created_by" json:"created_by"`
	CreatedDate *time.Time `db:"created_date" json:"created_date"`
	Descr       *string    `db:"descr" json:"descr"`
	Id          string     `db:"id" json:"id"`
	IsFinal     bool       `db:"is_final" json:"is_final"`
	IsSuccess   bool       `db:"is_success" json:"is_success"`
	Name        string     `db:"name" json:"name"`
	UpdatedBy   *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate *time.Time `db:"updated_date" json:"updated_date"`

	// has many
	OrderItemPlans []OrderItemPlan `json:"order_item_plans"`
}

// TableName sets the table name
func (OrderItemPlanStatus) TableName() string {
	return "order_item_plan_status"
}

// OrderItemRenewDomain

type OrderItemRenewDomain struct {
	AccreditationTldId string     `db:"accreditation_tld_id" json:"accreditation_tld_id"`
	CreatedBy          *string    `db:"created_by" json:"created_by"`
	CreatedDate        *time.Time `db:"created_date" json:"created_date"`
	CurrentExpiryDate  time.Time  `db:"current_expiry_date" json:"current_expiry_date"`
	Id                 string     `db:"id" json:"id"`
	Name               string     `db:"name" json:"name"`
	OrderId            string     `db:"order_id" json:"order_id"`
	ParentOrderItemId  *string    `db:"parent_order_item_id" json:"parent_order_item_id"`
	Period             int        `db:"period" json:"period"`
	StatusId           string     `db:"status_id" json:"status_id"`
	UpdatedBy          *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate        *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	Status           *OrderItemStatus  `json:"status"`
	Order            *Order            `json:"order"`
	AccreditationTld *AccreditationTld `json:"accreditation_tld"`

	// has many
	RenewDomainPlans []RenewDomainPlan `json:"renew_domain_plans"`
}

// TableName sets the table name
func (OrderItemRenewDomain) TableName() string {
	return "order_item_renew_domain"
}

// OrderItemStatus

type OrderItemStatus struct {
	Descr     string `db:"descr" json:"descr"`
	Id        string `db:"id" json:"id"`
	IsFinal   bool   `db:"is_final" json:"is_final"`
	IsSuccess bool   `db:"is_success" json:"is_success"`
	Name      string `db:"name" json:"name"`

	// has many
	OrderItems              []OrderItem              `json:"order_items"`
	OrderItemCreateContacts []OrderItemCreateContact `json:"order_item_create_contacts"`
	OrderItemCreateDomains  []OrderItemCreateDomain  `json:"order_item_create_domains"`
	OrderItemRenewDomains   []OrderItemRenewDomain   `json:"order_item_renew_domains"`
}

// TableName sets the table name
func (OrderItemStatus) TableName() string {
	return "order_item_status"
}

// OrderItemStrategy

type OrderItemStrategy struct {
	Id                 string  `db:"id" json:"id"`
	ObjectId           string  `db:"object_id" json:"object_id"`
	OrderTypeId        string  `db:"order_type_id" json:"order_type_id"`
	ProviderInstanceId *string `db:"provider_instance_id" json:"provider_instance_id"`
	ProvisionOrder     int     `db:"provision_order" json:"provision_order"`

	// belongs to
	OrderType        *OrderType        `json:"order_type"`
	ProviderInstance *ProviderInstance `json:"provider_instance"`
	Object           *OrderItemObject  `json:"object"`
}

// TableName sets the table name
func (OrderItemStrategy) TableName() string {
	return "order_item_strategy"
}

// OrderStatus

type OrderStatus struct {
	Descr     string `db:"descr" json:"descr"`
	Id        string `db:"id" json:"id"`
	IsFinal   bool   `db:"is_final" json:"is_final"`
	IsSuccess bool   `db:"is_success" json:"is_success"`
	Name      string `db:"name" json:"name"`

	// has many
	Orders                 []Order                 `json:"orders"`
	OrderStatusTransitions []OrderStatusTransition `json:"order_status_transitions"`
}

// TableName sets the table name
func (OrderStatus) TableName() string {
	return "order_status"
}

// OrderStatusPath
// Names the valid "paths" that an order can take, this allows for
// flexibility on the possibility of using multiple payment methods that may
// or may not offer auth/capture.
type OrderStatusPath struct {
	Descr *string `db:"descr" json:"descr"`
	Id    string  `db:"id" json:"id"`
	Name  string  `db:"name" json:"name"`

	// has many
	Orders                 []Order                 `json:"orders"`
	OrderStatusTransitions []OrderStatusTransition `json:"order_status_transitions"`
}

// TableName sets the table name
func (OrderStatusPath) TableName() string {
	return "order_status_path"
}

// OrderStatusTransition
// tuples in this table become valid status transitions for orders
type OrderStatusTransition struct {
	FromId string `db:"from_id" json:"from_id"`
	Id     string `db:"id" json:"id"`
	PathId string `db:"path_id" json:"path_id"`
	ToId   string `db:"to_id" json:"to_id"`

	// belongs to
	To   *OrderStatus     `json:"to"`
	Path *OrderStatusPath `json:"path"`
	From *OrderStatus     `json:"from"`
}

// TableName sets the table name
func (OrderStatusTransition) TableName() string {
	return "order_status_transition"
}

// OrderType

type OrderType struct {
	Id        string `db:"id" json:"id"`
	Name      string `db:"name" json:"name"`
	ProductId string `db:"product_id" json:"product_id"`

	// belongs to
	Product *Product `json:"product"`

	// has many
	Orders             []Order             `json:"orders"`
	OrderItemStrategys []OrderItemStrategy `json:"order_item_strategys"`
}

// TableName sets the table name
func (OrderType) TableName() string {
	return "order_type"
}

// PgAllForeignKeys

type PgAllForeignKeys struct {
	FkColumns        string  `db:"fk_columns" json:"fk_columns"`
	FkConstraintName *string `db:"fk_constraint_name" json:"fk_constraint_name"`
	FkSchemaName     *string `db:"fk_schema_name" json:"fk_schema_name"`
	FkTableName      *string `db:"fk_table_name" json:"fk_table_name"`
	FkTableOid       string  `db:"fk_table_oid" json:"fk_table_oid"`
	IsDeferrable     *bool   `db:"is_deferrable" json:"is_deferrable"`
	IsDeferred       *bool   `db:"is_deferred" json:"is_deferred"`
	MatchType        *string `db:"match_type" json:"match_type"`
	OnDelete         *string `db:"on_delete" json:"on_delete"`
	OnUpdate         *string `db:"on_update" json:"on_update"`
	PkColumns        string  `db:"pk_columns" json:"pk_columns"`
	PkConstraintName *string `db:"pk_constraint_name" json:"pk_constraint_name"`
	PkIndexName      *string `db:"pk_index_name" json:"pk_index_name"`
	PkSchemaName     *string `db:"pk_schema_name" json:"pk_schema_name"`
	PkTableName      *string `db:"pk_table_name" json:"pk_table_name"`
	PkTableOid       string  `db:"pk_table_oid" json:"pk_table_oid"`
}

// TableName sets the table name
func (PgAllForeignKeys) TableName() string {
	return "pg_all_foreign_keys"
}

// Product

type Product struct {
	Id   string `db:"id" json:"id"`
	Name string `db:"name" json:"name"`

	// has many
	OrderTypes []OrderType `json:"order_types"`
}

// TableName sets the table name
func (Product) TableName() string {
	return "product"
}

// Provider

type Provider struct {
	BusinessEntityId string     `db:"business_entity_id" json:"business_entity_id"`
	CreatedBy        *string    `db:"created_by" json:"created_by"`
	CreatedDate      *time.Time `db:"created_date" json:"created_date"`
	Descr            *string    `db:"descr" json:"descr"`
	Id               string     `db:"id" json:"id"`
	Name             string     `db:"name" json:"name"`
	UpdatedBy        *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate      *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	BusinessEntity *BusinessEntity `json:"business_entity"`

	// has many
	ProviderInstances []ProviderInstance `json:"provider_instances"`
	ProviderProtocols []ProviderProtocol `json:"provider_protocols"`
}

// TableName sets the table name
func (Provider) TableName() string {
	return "provider"
}

// ProviderInstance
// within a backend provider, there can be multiple instances, which could
// represent customers or simply buckets where the tlds are placed, each one
// of these are considered instances each one with its own credentials, etc.
type ProviderInstance struct {
	CreatedBy   *string    `db:"created_by" json:"created_by"`
	CreatedDate *time.Time `db:"created_date" json:"created_date"`
	Descr       *string    `db:"descr" json:"descr"`
	Id          string     `db:"id" json:"id"`
	// whether this provider is forwarding requests to another (hexonet,
	// opensrs, etc.)
	IsProxy     *bool      `db:"is_proxy" json:"is_proxy"`
	Name        string     `db:"name" json:"name"`
	ProviderId  string     `db:"provider_id" json:"provider_id"`
	UpdatedBy   *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	Provider *Provider `json:"provider"`

	// has many
	Accreditations        []Accreditation        `json:"accreditations"`
	OrderItemStrategys    []OrderItemStrategy    `json:"order_item_strategys"`
	ProviderInstanceEpps  []ProviderInstanceEpp  `json:"provider_instance_epps"`
	ProviderInstanceHttps []ProviderInstanceHttp `json:"provider_instance_https"`
	ProviderInstanceTlds  []ProviderInstanceTld  `json:"provider_instance_tlds"`
}

// TableName sets the table name
func (ProviderInstance) TableName() string {
	return "provider_instance"
}

// ProviderInstanceEpp

type ProviderInstanceEpp struct {
	ConnMax            *int    `db:"conn_max" json:"conn_max"`
	ConnMin            *int    `db:"conn_min" json:"conn_min"`
	Host               *string `db:"host" json:"host"`
	Id                 string  `db:"id" json:"id"`
	Port               *int    `db:"port" json:"port"`
	ProviderInstanceId string  `db:"provider_instance_id" json:"provider_instance_id"`

	// belongs to
	ProviderInstance *ProviderInstance `json:"provider_instance"`

	// has many
	ProviderInstanceEppExts []ProviderInstanceEppExt `json:"provider_instance_epp_exts"`
}

// TableName sets the table name
func (ProviderInstanceEpp) TableName() string {
	return "provider_instance_epp"
}

// ProviderInstanceEppExt

type ProviderInstanceEppExt struct {
	CreatedBy             *string    `db:"created_by" json:"created_by"`
	CreatedDate           *time.Time `db:"created_date" json:"created_date"`
	EppExtensionId        string     `db:"epp_extension_id" json:"epp_extension_id"`
	Id                    string     `db:"id" json:"id"`
	ProviderInstanceEppId string     `db:"provider_instance_epp_id" json:"provider_instance_epp_id"`
	UpdatedBy             *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate           *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	EppExtension        *EppExtension        `json:"epp_extension"`
	ProviderInstanceEpp *ProviderInstanceEpp `json:"provider_instance_epp"`
}

// TableName sets the table name
func (ProviderInstanceEppExt) TableName() string {
	return "provider_instance_epp_ext"
}

// ProviderInstanceHttp

type ProviderInstanceHttp struct {
	ApiKey             *string `db:"api_key" json:"api_key"`
	Id                 string  `db:"id" json:"id"`
	ProviderInstanceId string  `db:"provider_instance_id" json:"provider_instance_id"`
	Url                *string `db:"url" json:"url"`

	// belongs to
	ProviderInstance *ProviderInstance `json:"provider_instance"`
}

// TableName sets the table name
func (ProviderInstanceHttp) TableName() string {
	return "provider_instance_http"
}

// ProviderInstanceTld

type ProviderInstanceTld struct {
	CreatedBy          *string    `db:"created_by" json:"created_by"`
	CreatedDate        *time.Time `db:"created_date" json:"created_date"`
	Id                 string     `db:"id" json:"id"`
	ProviderInstanceId string     `db:"provider_instance_id" json:"provider_instance_id"`
	// This attribute serves to limit the applicablity of a relation over
	// time.
	// A constraint named service_range_unique ensures that for a given
	// instance_id, tld_id, there is no overlap of the service range.
	ServiceRange string     `db:"service_range" json:"service_range"`
	TldId        string     `db:"tld_id" json:"tld_id"`
	UpdatedBy    *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate  *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	Tld              *Tld              `json:"tld"`
	ProviderInstance *ProviderInstance `json:"provider_instance"`

	// has many
	AccreditationTlds []AccreditationTld `json:"accreditation_tlds"`
}

// TableName sets the table name
func (ProviderInstanceTld) TableName() string {
	return "provider_instance_tld"
}

// ProviderProtocol

type ProviderProtocol struct {
	CreatedBy           *string    `db:"created_by" json:"created_by"`
	CreatedDate         *time.Time `db:"created_date" json:"created_date"`
	Id                  string     `db:"id" json:"id"`
	IsEnabled           bool       `db:"is_enabled" json:"is_enabled"`
	ProviderId          string     `db:"provider_id" json:"provider_id"`
	SupportedProtocolId string     `db:"supported_protocol_id" json:"supported_protocol_id"`
	UpdatedBy           *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate         *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	SupportedProtocol *SupportedProtocol `json:"supported_protocol"`
	Provider          *Provider          `json:"provider"`
}

// TableName sets the table name
func (ProviderProtocol) TableName() string {
	return "provider_protocol"
}

// ProvisionContact

type ProvisionContact struct {
	AccreditationId  string         `db:"accreditation_id" json:"accreditation_id"`
	ContactId        string         `db:"contact_id" json:"contact_id"`
	CreatedBy        *string        `db:"created_by" json:"created_by"`
	CreatedDate      *time.Time     `db:"created_date" json:"created_date"`
	Handle           *string        `db:"handle" json:"handle"`
	Id               string         `db:"id" json:"id"`
	JobId            *string        `db:"job_id" json:"job_id"`
	OrderItemPlanIds string         `db:"order_item_plan_ids" json:"order_item_plan_ids"`
	ProvisionedDate  *time.Time     `db:"provisioned_date" json:"provisioned_date"`
	Pw               string         `db:"pw" json:"pw"`
	ResultData       types.JSONText `db:"result_data" json:"result_data"`
	ResultMessage    *string        `db:"result_message" json:"result_message"`
	Roid             *string        `db:"roid" json:"roid"`
	StatusId         string         `db:"status_id" json:"status_id"`
	TenantCustomerId string         `db:"tenant_customer_id" json:"tenant_customer_id"`
	UpdatedBy        *string        `db:"updated_by" json:"updated_by"`
	UpdatedDate      *time.Time     `db:"updated_date" json:"updated_date"`

	// belongs to
	Status         *ProvisionStatus `json:"status"`
	Contact        *Contact         `json:"contact"`
	TenantCustomer *TenantCustomer  `json:"tenant_customer"`
}

// TableName sets the table name
func (ProvisionContact) TableName() string {
	return "provision_contact"
}

// ProvisionDomain

type ProvisionDomain struct {
	AccreditationId    string         `db:"accreditation_id" json:"accreditation_id"`
	AccreditationTldId string         `db:"accreditation_tld_id" json:"accreditation_tld_id"`
	CreatedBy          *string        `db:"created_by" json:"created_by"`
	CreatedDate        *time.Time     `db:"created_date" json:"created_date"`
	Id                 string         `db:"id" json:"id"`
	IsComplete         bool           `db:"is_complete" json:"is_complete"`
	JobId              *string        `db:"job_id" json:"job_id"`
	Name               string         `db:"name" json:"name"`
	OrderItemPlanIds   string         `db:"order_item_plan_ids" json:"order_item_plan_ids"`
	ProvisionedDate    *time.Time     `db:"provisioned_date" json:"provisioned_date"`
	Pw                 string         `db:"pw" json:"pw"`
	RegistrationPeriod int            `db:"registration_period" json:"registration_period"`
	ResultData         types.JSONText `db:"result_data" json:"result_data"`
	ResultMessage      *string        `db:"result_message" json:"result_message"`
	Roid               *string        `db:"roid" json:"roid"`
	RyCreatedDate      *time.Time     `db:"ry_created_date" json:"ry_created_date"`
	RyExpiryDate       *time.Time     `db:"ry_expiry_date" json:"ry_expiry_date"`
	StatusId           string         `db:"status_id" json:"status_id"`
	TenantCustomerId   string         `db:"tenant_customer_id" json:"tenant_customer_id"`
	UpdatedBy          *string        `db:"updated_by" json:"updated_by"`
	UpdatedDate        *time.Time     `db:"updated_date" json:"updated_date"`

	// belongs to
	AccreditationTld *AccreditationTld `json:"accreditation_tld"`
	TenantCustomer   *TenantCustomer   `json:"tenant_customer"`
	Status           *ProvisionStatus  `json:"status"`

	// has many
	ProvisionDomainContacts []ProvisionDomainContact `json:"provision_domain_contacts"`
	ProvisionDomainHosts    []ProvisionDomainHost    `json:"provision_domain_hosts"`
}

// TableName sets the table name
func (ProvisionDomain) TableName() string {
	return "provision_domain"
}

// ProvisionDomainContact

type ProvisionDomainContact struct {
	ContactId         string     `db:"contact_id" json:"contact_id"`
	ContactTypeId     string     `db:"contact_type_id" json:"contact_type_id"`
	CreatedBy         *string    `db:"created_by" json:"created_by"`
	CreatedDate       *time.Time `db:"created_date" json:"created_date"`
	Id                string     `db:"id" json:"id"`
	ProvisionDomainId string     `db:"provision_domain_id" json:"provision_domain_id"`
	UpdatedBy         *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate       *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	ContactType     *DomainContactType `json:"contact_type"`
	ProvisionDomain *ProvisionDomain   `json:"provision_domain"`
	Contact         *Contact           `json:"contact"`
}

// TableName sets the table name
func (ProvisionDomainContact) TableName() string {
	return "provision_domain_contact"
}

// ProvisionDomainHost

type ProvisionDomainHost struct {
	CreatedBy         *string    `db:"created_by" json:"created_by"`
	CreatedDate       *time.Time `db:"created_date" json:"created_date"`
	HostId            string     `db:"host_id" json:"host_id"`
	Id                string     `db:"id" json:"id"`
	ProvisionDomainId string     `db:"provision_domain_id" json:"provision_domain_id"`
	UpdatedBy         *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate       *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	ProvisionDomain *ProvisionDomain `json:"provision_domain"`
	Host            *Host            `json:"host"`
}

// TableName sets the table name
func (ProvisionDomainHost) TableName() string {
	return "provision_domain_host"
}

// ProvisionDomainRenew

type ProvisionDomainRenew struct {
	AccreditationId   string         `db:"accreditation_id" json:"accreditation_id"`
	CreatedBy         *string        `db:"created_by" json:"created_by"`
	CreatedDate       *time.Time     `db:"created_date" json:"created_date"`
	CurrentExpiryDate time.Time      `db:"current_expiry_date" json:"current_expiry_date"`
	DomainId          *string        `db:"domain_id" json:"domain_id"`
	Id                string         `db:"id" json:"id"`
	IsAuto            bool           `db:"is_auto" json:"is_auto"`
	JobId             *string        `db:"job_id" json:"job_id"`
	OrderItemPlanIds  string         `db:"order_item_plan_ids" json:"order_item_plan_ids"`
	Period            int            `db:"period" json:"period"`
	ProvisionedDate   *time.Time     `db:"provisioned_date" json:"provisioned_date"`
	ResultData        types.JSONText `db:"result_data" json:"result_data"`
	ResultMessage     *string        `db:"result_message" json:"result_message"`
	Roid              *string        `db:"roid" json:"roid"`
	RyExpiryDate      *time.Time     `db:"ry_expiry_date" json:"ry_expiry_date"`
	StatusId          string         `db:"status_id" json:"status_id"`
	TenantCustomerId  string         `db:"tenant_customer_id" json:"tenant_customer_id"`
	UpdatedBy         *string        `db:"updated_by" json:"updated_by"`
	UpdatedDate       *time.Time     `db:"updated_date" json:"updated_date"`

	// belongs to
	Domain         *Domain          `json:"domain"`
	Status         *ProvisionStatus `json:"status"`
	TenantCustomer *TenantCustomer  `json:"tenant_customer"`
}

// TableName sets the table name
func (ProvisionDomainRenew) TableName() string {
	return "provision_domain_renew"
}

// ProvisionHost

type ProvisionHost struct {
	AccreditationId  string         `db:"accreditation_id" json:"accreditation_id"`
	CreatedBy        *string        `db:"created_by" json:"created_by"`
	CreatedDate      *time.Time     `db:"created_date" json:"created_date"`
	HostId           string         `db:"host_id" json:"host_id"`
	Id               string         `db:"id" json:"id"`
	JobId            *string        `db:"job_id" json:"job_id"`
	OrderItemPlanIds string         `db:"order_item_plan_ids" json:"order_item_plan_ids"`
	ProvisionedDate  *time.Time     `db:"provisioned_date" json:"provisioned_date"`
	ResultData       types.JSONText `db:"result_data" json:"result_data"`
	ResultMessage    *string        `db:"result_message" json:"result_message"`
	Roid             *string        `db:"roid" json:"roid"`
	StatusId         string         `db:"status_id" json:"status_id"`
	TenantCustomerId string         `db:"tenant_customer_id" json:"tenant_customer_id"`
	UpdatedBy        *string        `db:"updated_by" json:"updated_by"`
	UpdatedDate      *time.Time     `db:"updated_date" json:"updated_date"`

	// belongs to
	TenantCustomer *TenantCustomer  `json:"tenant_customer"`
	Host           *Host            `json:"host"`
	Status         *ProvisionStatus `json:"status"`
}

// TableName sets the table name
func (ProvisionHost) TableName() string {
	return "provision_host"
}

// ProvisionStatus

type ProvisionStatus struct {
	Descr     *string `db:"descr" json:"descr"`
	Id        string  `db:"id" json:"id"`
	IsFinal   bool    `db:"is_final" json:"is_final"`
	IsSuccess bool    `db:"is_success" json:"is_success"`
	Name      string  `db:"name" json:"name"`

	// has many
	ProvisionContacts     []ProvisionContact     `json:"provision_contacts"`
	ProvisionDomains      []ProvisionDomain      `json:"provision_domains"`
	ProvisionDomainRenews []ProvisionDomainRenew `json:"provision_domain_renews"`
	ProvisionHosts        []ProvisionHost        `json:"provision_hosts"`
}

// TableName sets the table name
func (ProvisionStatus) TableName() string {
	return "provision_status"
}

// Registry

type Registry struct {
	BusinessEntityId string     `db:"business_entity_id" json:"business_entity_id"`
	CreatedBy        *string    `db:"created_by" json:"created_by"`
	CreatedDate      *time.Time `db:"created_date" json:"created_date"`
	Descr            *string    `db:"descr" json:"descr"`
	Id               string     `db:"id" json:"id"`
	Name             string     `db:"name" json:"name"`
	UpdatedBy        *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate      *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	BusinessEntity *BusinessEntity `json:"business_entity"`

	// has many
	Tlds []Tld `json:"tlds"`
}

// TableName sets the table name
func (Registry) TableName() string {
	return "registry"
}

// RenewDomainPlan

type RenewDomainPlan struct {
	CreatedBy         *string        `db:"created_by" json:"created_by"`
	CreatedDate       *time.Time     `db:"created_date" json:"created_date"`
	Id                string         `db:"id" json:"id"`
	OrderItemId       string         `db:"order_item_id" json:"order_item_id"`
	OrderItemObjectId string         `db:"order_item_object_id" json:"order_item_object_id"`
	ParentId          *string        `db:"parent_id" json:"parent_id"`
	ReferenceId       *string        `db:"reference_id" json:"reference_id"`
	ResultData        types.JSONText `db:"result_data" json:"result_data"`
	ResultMessage     *string        `db:"result_message" json:"result_message"`
	StatusId          string         `db:"status_id" json:"status_id"`
	UpdatedBy         *string        `db:"updated_by" json:"updated_by"`
	UpdatedDate       *time.Time     `db:"updated_date" json:"updated_date"`

	// belongs to
	OrderItem *OrderItemRenewDomain `json:"order_item"`
}

// TableName sets the table name
func (RenewDomainPlan) TableName() string {
	return "renew_domain_plan"
}

// SupportedProtocol

type SupportedProtocol struct {
	Descr *string `db:"descr" json:"descr"`
	Id    string  `db:"id" json:"id"`
	// Name of a protocol, like 'EPP', 'Hexonet HTTP', ...
	Name *string `db:"name" json:"name"`

	// has many
	ProviderProtocols []ProviderProtocol `json:"provider_protocols"`
}

// TableName sets the table name
func (SupportedProtocol) TableName() string {
	return "supported_protocol"
}

// TapFunky

type TapFunky struct {
	Args       *string `db:"args" json:"args"`
	IsDefiner  *bool   `db:"is_definer" json:"is_definer"`
	IsStrict   *bool   `db:"is_strict" json:"is_strict"`
	IsVisible  *bool   `db:"is_visible" json:"is_visible"`
	Kind       *string `db:"kind" json:"kind"`
	Langoid    string  `db:"langoid" json:"langoid"`
	Name       *string `db:"name" json:"name"`
	Oid        string  `db:"oid" json:"oid"`
	Owner      *string `db:"owner" json:"owner"`
	Returns    *string `db:"returns" json:"returns"`
	ReturnsSet *bool   `db:"returns_set" json:"returns_set"`
	Schema     *string `db:"schema" json:"schema"`
	Volatility *string `db:"volatility" json:"volatility"`
}

// TableName sets the table name
func (TapFunky) TableName() string {
	return "tap_funky"
}

// Tenant

type Tenant struct {
	BusinessEntityId string     `db:"business_entity_id" json:"business_entity_id"`
	CreatedBy        *string    `db:"created_by" json:"created_by"`
	CreatedDate      *time.Time `db:"created_date" json:"created_date"`
	DeletedBy        *string    `db:"deleted_by" json:"deleted_by"`
	DeletedDate      *time.Time `db:"deleted_date" json:"deleted_date"`
	Descr            string     `db:"descr" json:"descr"`
	Id               string     `db:"id" json:"id"`
	Name             string     `db:"name" json:"name"`
	UpdatedBy        *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate      *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	BusinessEntity *BusinessEntity `json:"business_entity"`

	// has many
	Accreditations  []Accreditation  `json:"accreditations"`
	TenantCustomers []TenantCustomer `json:"tenant_customers"`
}

// TableName sets the table name
func (Tenant) TableName() string {
	return "tenant"
}

// TenantCert

type TenantCert struct {
	CaId         string     `db:"ca_id" json:"ca_id"`
	Cert         *string    `db:"cert" json:"cert"`
	CreatedBy    *string    `db:"created_by" json:"created_by"`
	CreatedDate  *time.Time `db:"created_date" json:"created_date"`
	Id           string     `db:"id" json:"id"`
	Key          *string    `db:"key" json:"key"`
	Name         *string    `db:"name" json:"name"`
	ServiceRange string     `db:"service_range" json:"service_range"`
	UpdatedBy    *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate  *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	Ca *CertificateAuthority `json:"ca"`

	// has many
	AccreditationEpps []AccreditationEpp `json:"accreditation_epps"`
}

// TableName sets the table name
func (TenantCert) TableName() string {
	return "tenant_cert"
}

// TenantCustomer

type TenantCustomer struct {
	CreatedBy      *string    `db:"created_by" json:"created_by"`
	CreatedDate    *time.Time `db:"created_date" json:"created_date"`
	CustomerId     string     `db:"customer_id" json:"customer_id"`
	CustomerNumber string     `db:"customer_number" json:"customer_number"`
	DeletedBy      *string    `db:"deleted_by" json:"deleted_by"`
	DeletedDate    *time.Time `db:"deleted_date" json:"deleted_date"`
	Id             string     `db:"id" json:"id"`
	TenantId       string     `db:"tenant_id" json:"tenant_id"`
	UpdatedBy      *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate    *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	Tenant   *Tenant   `json:"tenant"`
	Customer *Customer `json:"customer"`

	// has many
	Contacts              []Contact              `json:"contacts"`
	Domains               []Domain               `json:"domains"`
	Hosts                 []Host                 `json:"hosts"`
	Jobs                  []Job                  `json:"jobs"`
	Orders                []Order                `json:"orders"`
	ProvisionContacts     []ProvisionContact     `json:"provision_contacts"`
	ProvisionDomains      []ProvisionDomain      `json:"provision_domains"`
	ProvisionDomainRenews []ProvisionDomainRenew `json:"provision_domain_renews"`
	ProvisionHosts        []ProvisionHost        `json:"provision_hosts"`
}

// TableName sets the table name
func (TenantCustomer) TableName() string {
	return "tenant_customer"
}

// Tld

type Tld struct {
	CreatedBy   *string    `db:"created_by" json:"created_by"`
	CreatedDate *time.Time `db:"created_date" json:"created_date"`
	Id          string     `db:"id" json:"id"`
	// The top level domain without a leading dot
	Name string `db:"name" json:"name"`
	// If top level domain is for instance co.uk this foreign key refers
	// to uk.
	ParentTldId *string    `db:"parent_tld_id" json:"parent_tld_id"`
	RegistryId  string     `db:"registry_id" json:"registry_id"`
	UpdatedBy   *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate *time.Time `db:"updated_date" json:"updated_date"`

	// belongs to
	Registry *Registry `json:"registry"`

	// has many
	ProviderInstanceTlds []ProviderInstanceTld `json:"provider_instance_tlds"`
	Tlds                 []Tld                 `json:"tlds"`
}

// TableName sets the table name
func (Tld) TableName() string {
	return "tld"
}

// User

type User struct {
	CreatedBy   *string    `db:"created_by" json:"created_by"`
	CreatedDate *time.Time `db:"created_date" json:"created_date"`
	DeletedBy   *string    `db:"deleted_by" json:"deleted_by"`
	DeletedDate *time.Time `db:"deleted_date" json:"deleted_date"`
	Email       string     `db:"email" json:"email"`
	Id          string     `db:"id" json:"id"`
	Name        string     `db:"name" json:"name"`
	UpdatedBy   *string    `db:"updated_by" json:"updated_by"`
	UpdatedDate *time.Time `db:"updated_date" json:"updated_date"`

	// has many
	CustomerUsers []CustomerUser `json:"customer_users"`
}

// TableName sets the table name
func (User) TableName() string {
	return "user"
}

// VAccreditation

type VAccreditation struct {
	AccreditationId      *string `db:"accreditation_id" json:"accreditation_id"`
	AccreditationName    *string `db:"accreditation_name" json:"accreditation_name"`
	IsProxy              *bool   `db:"is_proxy" json:"is_proxy"`
	ProviderId           *string `db:"provider_id" json:"provider_id"`
	ProviderInstanceId   *string `db:"provider_instance_id" json:"provider_instance_id"`
	ProviderInstanceName *string `db:"provider_instance_name" json:"provider_instance_name"`
	ProviderName         *string `db:"provider_name" json:"provider_name"`
	TenantId             *string `db:"tenant_id" json:"tenant_id"`
	TenantName           *string `db:"tenant_name" json:"tenant_name"`
}

// TableName sets the table name
func (VAccreditation) TableName() string {
	return "v_accreditation"
}

// VAccreditationEpp

type VAccreditationEpp struct {
	AccreditationEppId *string `db:"accreditation_epp_id" json:"accreditation_epp_id"`
	AccreditationId    *string `db:"accreditation_id" json:"accreditation_id"`
	AccreditationName  *string `db:"accreditation_name" json:"accreditation_name"`
	CertId             *string `db:"cert_id" json:"cert_id"`
	Clid               *string `db:"clid" json:"clid"`
	ConnMax            *int    `db:"conn_max" json:"conn_max"`
	ConnMin            *int    `db:"conn_min" json:"conn_min"`
	Host               *string `db:"host" json:"host"`
	Port               *int    `db:"port" json:"port"`
	ProviderId         *string `db:"provider_id" json:"provider_id"`
	ProviderName       *string `db:"provider_name" json:"provider_name"`
	Pw                 *string `db:"pw" json:"pw"`
	TenantId           *string `db:"tenant_id" json:"tenant_id"`
	TenantName         *string `db:"tenant_name" json:"tenant_name"`
}

// TableName sets the table name
func (VAccreditationEpp) TableName() string {
	return "v_accreditation_epp"
}

// VAccreditationTld

type VAccreditationTld struct {
	AccreditationId      *string `db:"accreditation_id" json:"accreditation_id"`
	AccreditationName    *string `db:"accreditation_name" json:"accreditation_name"`
	AccreditationTldId   *string `db:"accreditation_tld_id" json:"accreditation_tld_id"`
	CustomerId           *string `db:"customer_id" json:"customer_id"`
	CustomerName         *string `db:"customer_name" json:"customer_name"`
	IsDefault            *bool   `db:"is_default" json:"is_default"`
	IsProxy              *bool   `db:"is_proxy" json:"is_proxy"`
	ProviderId           *string `db:"provider_id" json:"provider_id"`
	ProviderInstanceId   *string `db:"provider_instance_id" json:"provider_instance_id"`
	ProviderInstanceName *string `db:"provider_instance_name" json:"provider_instance_name"`
	ProviderName         *string `db:"provider_name" json:"provider_name"`
	TenantCustomerId     *string `db:"tenant_customer_id" json:"tenant_customer_id"`
	TenantCustomerNumber *string `db:"tenant_customer_number" json:"tenant_customer_number"`
	TenantId             *string `db:"tenant_id" json:"tenant_id"`
	TldId                *string `db:"tld_id" json:"tld_id"`
	TldName              *string `db:"tld_name" json:"tld_name"`
}

// TableName sets the table name
func (VAccreditationTld) TableName() string {
	return "v_accreditation_tld"
}

// VContact

type VContact struct {
	Address1         *string        `db:"address1" json:"address1"`
	Address2         *string        `db:"address2" json:"address2"`
	Address3         *string        `db:"address3" json:"address3"`
	Attributes       types.JSONText `db:"attributes" json:"attributes"`
	City             *string        `db:"city" json:"city"`
	ContactType      *string        `db:"contact_type" json:"contact_type"`
	Country          *string        `db:"country" json:"country"`
	Documentation    pq.StringArray `db:"documentation" json:"documentation"`
	Email            *string        `db:"email" json:"email"`
	Fax              *string        `db:"fax" json:"fax"`
	FirstName        *string        `db:"first_name" json:"first_name"`
	Id               *string        `db:"id" json:"id"`
	IsInternational  *bool          `db:"is_international" json:"is_international"`
	Language         *string        `db:"language" json:"language"`
	LastName         *string        `db:"last_name" json:"last_name"`
	OrgDuns          *string        `db:"org_duns" json:"org_duns"`
	OrgName          *string        `db:"org_name" json:"org_name"`
	OrgReg           *string        `db:"org_reg" json:"org_reg"`
	OrgVat           *string        `db:"org_vat" json:"org_vat"`
	Phone            *string        `db:"phone" json:"phone"`
	PostalCode       *string        `db:"postal_code" json:"postal_code"`
	State            *string        `db:"state" json:"state"`
	Tags             pq.StringArray `db:"tags" json:"tags"`
	TenantCustomerId *string        `db:"tenant_customer_id" json:"tenant_customer_id"`
	Title            *string        `db:"title" json:"title"`
}

// TableName sets the table name
func (VContact) TableName() string {
	return "v_contact"
}

// VContactAttribute

type VContactAttribute struct {
	Attributes types.JSONText `db:"attributes" json:"attributes"`
	ContactId  *string        `db:"contact_id" json:"contact_id"`
}

// TableName sets the table name
func (VContactAttribute) TableName() string {
	return "v_contact_attribute"
}

// VCustomerUser

type VCustomerUser struct {
	CustomerDescr           *string    `db:"customer_descr" json:"customer_descr"`
	CustomerId              *string    `db:"customer_id" json:"customer_id"`
	CustomerName            *string    `db:"customer_name" json:"customer_name"`
	CustomerUserCreatedDate *time.Time `db:"customer_user_created_date" json:"customer_user_created_date"`
	CustomerUserUpdatedDate *time.Time `db:"customer_user_updated_date" json:"customer_user_updated_date"`
	Email                   *string    `db:"email" json:"email"`
	Id                      *string    `db:"id" json:"id"`
	Name                    *string    `db:"name" json:"name"`
	UserCreatedDate         *time.Time `db:"user_created_date" json:"user_created_date"`
	UserId                  *string    `db:"user_id" json:"user_id"`
	UserUpdatedDate         *time.Time `db:"user_updated_date" json:"user_updated_date"`
}

// TableName sets the table name
func (VCustomerUser) TableName() string {
	return "v_customer_user"
}

// VErrorDictionary

type VErrorDictionary struct {
	Category        *string        `db:"category" json:"category"`
	ColumnsAffected pq.StringArray `db:"columns_affected" json:"columns_affected"`
	Id              *int           `db:"id" json:"id"`
	Message         *string        `db:"message" json:"message"`
}

// TableName sets the table name
func (VErrorDictionary) TableName() string {
	return "v_error_dictionary"
}

// VJob

type VJob struct {
	CreatedDate      *time.Time     `db:"created_date" json:"created_date"`
	Data             types.JSONText `db:"data" json:"data"`
	EndDate          *time.Time     `db:"end_date" json:"end_date"`
	EventId          *string        `db:"event_id" json:"event_id"`
	JobId            *string        `db:"job_id" json:"job_id"`
	JobStatusIsFinal *bool          `db:"job_status_is_final" json:"job_status_is_final"`
	JobStatusName    *string        `db:"job_status_name" json:"job_status_name"`
	JobTypeName      *string        `db:"job_type_name" json:"job_type_name"`
	ReferenceId      *string        `db:"reference_id" json:"reference_id"`
	ReferenceTable   *string        `db:"reference_table" json:"reference_table"`
	ResultData       types.JSONText `db:"result_data" json:"result_data"`
	ResultMsg        *string        `db:"result_msg" json:"result_msg"`
	RetryCount       *int           `db:"retry_count" json:"retry_count"`
	RetryDate        *time.Time     `db:"retry_date" json:"retry_date"`
	RoutingKey       *string        `db:"routing_key" json:"routing_key"`
	StartDate        *time.Time     `db:"start_date" json:"start_date"`
	TenantCustomer   types.JSONText `db:"tenant_customer" json:"tenant_customer"`
	TenantCustomerId *string        `db:"tenant_customer_id" json:"tenant_customer_id"`
}

// TableName sets the table name
func (VJob) TableName() string {
	return "v_job"
}

// VJobHistory

type VJobHistory struct {
	CreatedDate   *time.Time `db:"created_date" json:"created_date"`
	EventId       *string    `db:"event_id" json:"event_id"`
	JobId         *string    `db:"job_id" json:"job_id"`
	JobTypeName   *string    `db:"job_type_name" json:"job_type_name"`
	Operation     *string    `db:"operation" json:"operation"`
	StatementDate *time.Time `db:"statement_date" json:"statement_date"`
	StatusName    *string    `db:"status_name" json:"status_name"`
}

// TableName sets the table name
func (VJobHistory) TableName() string {
	return "v_job_history"
}

// VOrder

type VOrder struct {
	CreatedDate          *time.Time `db:"created_date" json:"created_date"`
	CustomerId           *string    `db:"customer_id" json:"customer_id"`
	CustomerName         *string    `db:"customer_name" json:"customer_name"`
	Elapsed              *string    `db:"elapsed" json:"elapsed"`
	OrderId              *string    `db:"order_id" json:"order_id"`
	OrderPathId          *string    `db:"order_path_id" json:"order_path_id"`
	OrderPathName        *string    `db:"order_path_name" json:"order_path_name"`
	OrderStatusId        *string    `db:"order_status_id" json:"order_status_id"`
	OrderStatusIsFinal   *bool      `db:"order_status_is_final" json:"order_status_is_final"`
	OrderStatusIsSuccess *bool      `db:"order_status_is_success" json:"order_status_is_success"`
	OrderStatusName      *string    `db:"order_status_name" json:"order_status_name"`
	OrderTypeId          *string    `db:"order_type_id" json:"order_type_id"`
	OrderTypeName        *string    `db:"order_type_name" json:"order_type_name"`
	ProductId            *string    `db:"product_id" json:"product_id"`
	ProductName          *string    `db:"product_name" json:"product_name"`
	TenantCustomerId     *string    `db:"tenant_customer_id" json:"tenant_customer_id"`
	TenantId             *string    `db:"tenant_id" json:"tenant_id"`
	TenantName           *string    `db:"tenant_name" json:"tenant_name"`
	UpdatedDate          *time.Time `db:"updated_date" json:"updated_date"`
}

// TableName sets the table name
func (VOrder) TableName() string {
	return "v_order"
}

// VOrderCreateContact

type VOrderCreateContact struct {
	ContactType      *string `db:"contact_type" json:"contact_type"`
	CustomerId       *string `db:"customer_id" json:"customer_id"`
	CustomerUserId   *string `db:"customer_user_id" json:"customer_user_id"`
	FirstName        *string `db:"first_name" json:"first_name"`
	LastName         *string `db:"last_name" json:"last_name"`
	Name             *string `db:"name" json:"name"`
	OrderId          *string `db:"order_id" json:"order_id"`
	OrderItemId      *string `db:"order_item_id" json:"order_item_id"`
	OrgName          *string `db:"org_name" json:"org_name"`
	StatusDescr      *string `db:"status_descr" json:"status_descr"`
	StatusId         *string `db:"status_id" json:"status_id"`
	StatusName       *string `db:"status_name" json:"status_name"`
	TenantCustomerId *string `db:"tenant_customer_id" json:"tenant_customer_id"`
	TenantId         *string `db:"tenant_id" json:"tenant_id"`
	TenantName       *string `db:"tenant_name" json:"tenant_name"`
	TypeId           *string `db:"type_id" json:"type_id"`
}

// TableName sets the table name
func (VOrderCreateContact) TableName() string {
	return "v_order_create_contact"
}

// VOrderCreateDomain

type VOrderCreateDomain struct {
	AccreditationId      *string `db:"accreditation_id" json:"accreditation_id"`
	AccreditationTldId   *string `db:"accreditation_tld_id" json:"accreditation_tld_id"`
	CustomerId           *string `db:"customer_id" json:"customer_id"`
	CustomerUserId       *string `db:"customer_user_id" json:"customer_user_id"`
	DomainName           *string `db:"domain_name" json:"domain_name"`
	Name                 *string `db:"name" json:"name"`
	OrderId              *string `db:"order_id" json:"order_id"`
	OrderItemId          *string `db:"order_item_id" json:"order_item_id"`
	ProviderInstanceId   *string `db:"provider_instance_id" json:"provider_instance_id"`
	ProviderInstanceName *string `db:"provider_instance_name" json:"provider_instance_name"`
	ProviderName         *string `db:"provider_name" json:"provider_name"`
	RegistrationPeriod   *int    `db:"registration_period" json:"registration_period"`
	StatusDescr          *string `db:"status_descr" json:"status_descr"`
	StatusId             *string `db:"status_id" json:"status_id"`
	StatusName           *string `db:"status_name" json:"status_name"`
	TenantCustomerId     *string `db:"tenant_customer_id" json:"tenant_customer_id"`
	TenantId             *string `db:"tenant_id" json:"tenant_id"`
	TenantName           *string `db:"tenant_name" json:"tenant_name"`
	TldId                *string `db:"tld_id" json:"tld_id"`
	TldName              *string `db:"tld_name" json:"tld_name"`
	TypeId               *string `db:"type_id" json:"type_id"`
}

// TableName sets the table name
func (VOrderCreateDomain) TableName() string {
	return "v_order_create_domain"
}

// VOrderItemPlan

type VOrderItemPlan struct {
	Depth               *int    `db:"depth" json:"depth"`
	Id                  *string `db:"id" json:"id"`
	ObjectId            *string `db:"object_id" json:"object_id"`
	ObjectName          *string `db:"object_name" json:"object_name"`
	OrderId             *string `db:"order_id" json:"order_id"`
	OrderItemId         *string `db:"order_item_id" json:"order_item_id"`
	OrderTypeId         *string `db:"order_type_id" json:"order_type_id"`
	OrderTypeName       *string `db:"order_type_name" json:"order_type_name"`
	ParentId            *string `db:"parent_id" json:"parent_id"`
	ParentObjectName    *string `db:"parent_object_name" json:"parent_object_name"`
	PlanStatusId        *string `db:"plan_status_id" json:"plan_status_id"`
	PlanStatusIsFinal   *bool   `db:"plan_status_is_final" json:"plan_status_is_final"`
	PlanStatusIsSuccess *bool   `db:"plan_status_is_success" json:"plan_status_is_success"`
	PlanStatusName      *string `db:"plan_status_name" json:"plan_status_name"`
	ProductId           *string `db:"product_id" json:"product_id"`
	ProductName         *string `db:"product_name" json:"product_name"`
	ReferenceId         *string `db:"reference_id" json:"reference_id"`
}

// TableName sets the table name
func (VOrderItemPlan) TableName() string {
	return "v_order_item_plan"
}

// VOrderItemPlanObject

type VOrderItemPlanObject struct {
	Id            *string `db:"id" json:"id"`
	ObjectId      *string `db:"object_id" json:"object_id"`
	ObjectName    *string `db:"object_name" json:"object_name"`
	OrderItemId   *string `db:"order_item_id" json:"order_item_id"`
	OrderTypeName *string `db:"order_type_name" json:"order_type_name"`
	ProductName   *string `db:"product_name" json:"product_name"`
}

// TableName sets the table name
func (VOrderItemPlanObject) TableName() string {
	return "v_order_item_plan_object"
}

// VOrderItemPlanStatus

type VOrderItemPlanStatus struct {
	Depth           *int           `db:"depth" json:"depth"`
	ObjectIds       string         `db:"object_ids" json:"object_ids"`
	Objects         pq.StringArray `db:"objects" json:"objects"`
	OrderId         *string        `db:"order_id" json:"order_id"`
	OrderItemId     *string        `db:"order_item_id" json:"order_item_id"`
	Total           *int64         `db:"total" json:"total"`
	TotalFail       *int64         `db:"total_fail" json:"total_fail"`
	TotalNew        *int64         `db:"total_new" json:"total_new"`
	TotalProcessing *int64         `db:"total_processing" json:"total_processing"`
	TotalSuccess    *int64         `db:"total_success" json:"total_success"`
}

// TableName sets the table name
func (VOrderItemPlanStatus) TableName() string {
	return "v_order_item_plan_status"
}

// VOrderItemStrategy

type VOrderItemStrategy struct {
	IsDefault      *bool   `db:"is_default" json:"is_default"`
	ObjectId       *string `db:"object_id" json:"object_id"`
	ObjectName     *string `db:"object_name" json:"object_name"`
	OrderTypeId    *string `db:"order_type_id" json:"order_type_id"`
	OrderTypeName  *string `db:"order_type_name" json:"order_type_name"`
	ProductId      *string `db:"product_id" json:"product_id"`
	ProductName    *string `db:"product_name" json:"product_name"`
	ProvisionOrder *int    `db:"provision_order" json:"provision_order"`
}

// TableName sets the table name
func (VOrderItemStrategy) TableName() string {
	return "v_order_item_strategy"
}

// VOrderProductType

type VOrderProductType struct {
	ProductId   *string `db:"product_id" json:"product_id"`
	ProductName *string `db:"product_name" json:"product_name"`
	RelName     *string `db:"rel_name" json:"rel_name"`
	TypeId      *string `db:"type_id" json:"type_id"`
	TypeName    *string `db:"type_name" json:"type_name"`
}

// TableName sets the table name
func (VOrderProductType) TableName() string {
	return "v_order_product_type"
}

// VOrderRenewDomain

type VOrderRenewDomain struct {
	AccreditationId      *string    `db:"accreditation_id" json:"accreditation_id"`
	AccreditationTldId   *string    `db:"accreditation_tld_id" json:"accreditation_tld_id"`
	CurrentExpiryDate    *time.Time `db:"current_expiry_date" json:"current_expiry_date"`
	CustomerId           *string    `db:"customer_id" json:"customer_id"`
	CustomerUserId       *string    `db:"customer_user_id" json:"customer_user_id"`
	DomainId             *string    `db:"domain_id" json:"domain_id"`
	DomainName           *string    `db:"domain_name" json:"domain_name"`
	Name                 *string    `db:"name" json:"name"`
	OrderId              *string    `db:"order_id" json:"order_id"`
	OrderItemId          *string    `db:"order_item_id" json:"order_item_id"`
	Period               *int       `db:"period" json:"period"`
	ProviderInstanceId   *string    `db:"provider_instance_id" json:"provider_instance_id"`
	ProviderInstanceName *string    `db:"provider_instance_name" json:"provider_instance_name"`
	ProviderName         *string    `db:"provider_name" json:"provider_name"`
	StatusDescr          *string    `db:"status_descr" json:"status_descr"`
	StatusId             *string    `db:"status_id" json:"status_id"`
	StatusName           *string    `db:"status_name" json:"status_name"`
	TenantCustomerId     *string    `db:"tenant_customer_id" json:"tenant_customer_id"`
	TenantId             *string    `db:"tenant_id" json:"tenant_id"`
	TenantName           *string    `db:"tenant_name" json:"tenant_name"`
	TldId                *string    `db:"tld_id" json:"tld_id"`
	TldName              *string    `db:"tld_name" json:"tld_name"`
	TypeId               *string    `db:"type_id" json:"type_id"`
}

// TableName sets the table name
func (VOrderRenewDomain) TableName() string {
	return "v_order_renew_domain"
}

// VOrderStatusTransition

type VOrderStatusTransition struct {
	FromStatus      *string `db:"from_status" json:"from_status"`
	IsFinal         *bool   `db:"is_final" json:"is_final"`
	IsSourceSuccess *bool   `db:"is_source_success" json:"is_source_success"`
	IsTargetSuccess *bool   `db:"is_target_success" json:"is_target_success"`
	PathId          *string `db:"path_id" json:"path_id"`
	PathName        *string `db:"path_name" json:"path_name"`
	SourceStatusId  *string `db:"source_status_id" json:"source_status_id"`
	TargetStatusId  *string `db:"target_status_id" json:"target_status_id"`
	ToStatus        *string `db:"to_status" json:"to_status"`
}

// TableName sets the table name
func (VOrderStatusTransition) TableName() string {
	return "v_order_status_transition"
}

// VOrderType

type VOrderType struct {
	Id          *string `db:"id" json:"id"`
	Name        *string `db:"name" json:"name"`
	ProductId   *string `db:"product_id" json:"product_id"`
	ProductName *string `db:"product_name" json:"product_name"`
}

// TableName sets the table name
func (VOrderType) TableName() string {
	return "v_order_type"
}

// VProviderInstanceOrderItemStrategy

type VProviderInstanceOrderItemStrategy struct {
	IsDefault            *bool   `db:"is_default" json:"is_default"`
	ObjectId             *string `db:"object_id" json:"object_id"`
	ObjectName           *string `db:"object_name" json:"object_name"`
	OrderTypeId          *string `db:"order_type_id" json:"order_type_id"`
	OrderTypeName        *string `db:"order_type_name" json:"order_type_name"`
	ProductId            *string `db:"product_id" json:"product_id"`
	ProductName          *string `db:"product_name" json:"product_name"`
	ProviderId           *string `db:"provider_id" json:"provider_id"`
	ProviderInstanceId   *string `db:"provider_instance_id" json:"provider_instance_id"`
	ProviderInstanceName *string `db:"provider_instance_name" json:"provider_instance_name"`
	ProviderName         *string `db:"provider_name" json:"provider_name"`
	ProvisionOrder       *int    `db:"provision_order" json:"provision_order"`
}

// TableName sets the table name
func (VProviderInstanceOrderItemStrategy) TableName() string {
	return "v_provider_instance_order_item_strategy"
}

// VTenantCustomer

type VTenantCustomer struct {
	CustomerCreatedDate       *time.Time `db:"customer_created_date" json:"customer_created_date"`
	CustomerId                *string    `db:"customer_id" json:"customer_id"`
	CustomerNumber            *string    `db:"customer_number" json:"customer_number"`
	CustomerUpdatedDate       *time.Time `db:"customer_updated_date" json:"customer_updated_date"`
	Descr                     *string    `db:"descr" json:"descr"`
	Id                        *string    `db:"id" json:"id"`
	Name                      *string    `db:"name" json:"name"`
	TenantCustomerCreatedDate *time.Time `db:"tenant_customer_created_date" json:"tenant_customer_created_date"`
	TenantCustomerUpdatedDate *time.Time `db:"tenant_customer_updated_date" json:"tenant_customer_updated_date"`
	TenantDescr               *string    `db:"tenant_descr" json:"tenant_descr"`
	TenantId                  *string    `db:"tenant_id" json:"tenant_id"`
	TenantName                *string    `db:"tenant_name" json:"tenant_name"`
}

// TableName sets the table name
func (VTenantCustomer) TableName() string {
	return "v_tenant_customer"
}
