// Code generated by gorm.io/gen. DO NOT EDIT.
// Code generated by gorm.io/gen. DO NOT EDIT.
// Code generated by gorm.io/gen. DO NOT EDIT.

package model

import (
	"time"
)

const TableNameHosting = "hosting"

// Hosting mapped from table <hosting>
type Hosting struct {
	CreatedDate      *time.Time `gorm:"column:created_date;type:timestamp with time zone;default:now()" json:"created_date"`
	UpdatedDate      *time.Time `gorm:"column:updated_date;type:timestamp with time zone" json:"updated_date"`
	CreatedBy        *string    `gorm:"column:created_by;type:text;default:CURRENT_USER" json:"created_by"`
	UpdatedBy        *string    `gorm:"column:updated_by;type:text" json:"updated_by"`
	ID               string     `gorm:"column:id;type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	DomainName       string     `gorm:"column:domain_name;type:fqdn;not null" json:"domain_name"`
	ProductID        string     `gorm:"column:product_id;type:uuid;not null" json:"product_id"`
	RegionID         string     `gorm:"column:region_id;type:uuid;not null" json:"region_id"`
	ClientID         string     `gorm:"column:client_id;type:uuid;not null" json:"client_id"`
	TenantCustomerID string     `gorm:"column:tenant_customer_id;type:uuid;not null" json:"tenant_customer_id"`
	CertificateID    *string    `gorm:"column:certificate_id;type:uuid" json:"certificate_id"`
	HostingStatusID  *string    `gorm:"column:hosting_status_id;type:uuid" json:"hosting_status_id"`
	Descr            *string    `gorm:"column:descr;type:text" json:"descr"`
	IsActive         bool       `gorm:"column:is_active;type:boolean;not null" json:"is_active"`
	IsDeleted        bool       `gorm:"column:is_deleted;type:boolean;not null" json:"is_deleted"`
	ExternalOrderID  *string    `gorm:"column:external_order_id;type:text" json:"external_order_id"`
	Tags             *string    `gorm:"column:tags;type:text[]" json:"tags"`
	Metadata         *string    `gorm:"column:metadata;type:jsonb;default:{}" json:"metadata"`
	StatusReason     *string    `gorm:"column:status_reason;type:text" json:"status_reason"`

	Certificate *HostingCertificate
	Client      HostingClient
	Product     HostingProduct
}

// TableName Hosting's table name
func (*Hosting) TableName() string {
	return TableNameHosting
}
