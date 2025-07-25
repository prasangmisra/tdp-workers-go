// Code generated by gorm.io/gen. DO NOT EDIT.
// Code generated by gorm.io/gen. DO NOT EDIT.
// Code generated by gorm.io/gen. DO NOT EDIT.

package model

import (
	"time"
)

const TableNameHostingClient = "hosting_client"

// HostingClient mapped from table <hosting_client>
type HostingClient struct {
	CreatedDate      *time.Time `gorm:"column:created_date;default:now()" json:"created_date"`
	UpdatedDate      *time.Time `gorm:"column:updated_date" json:"updated_date"`
	CreatedBy        *string    `gorm:"column:created_by;default:CURRENT_USER" json:"created_by"`
	UpdatedBy        *string    `gorm:"column:updated_by" json:"updated_by"`
	ID               string     `gorm:"column:id;primaryKey" json:"id"`
	TenantCustomerID string     `gorm:"column:tenant_customer_id;type:uuid;not null" json:"tenant_customer_id"`
	ExternalClientID *string    `gorm:"column:external_client_id;type:text" json:"external_client_id"`
	Name             *string    `gorm:"column:name" json:"name"`
	Email            string     `gorm:"column:email;not null" json:"email"`
	Username         *string    `gorm:"column:username" json:"username"`
	Password         *string    `gorm:"column:password" json:"password"`
	IsActive         bool       `gorm:"column:is_active;not null" json:"is_active"`
}

// TableName HostingClient's table name
func (*HostingClient) TableName() string {
	return TableNameHostingClient
}
