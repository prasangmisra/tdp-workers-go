// Code generated by gorm.io/gen. DO NOT EDIT.
// Code generated by gorm.io/gen. DO NOT EDIT.
// Code generated by gorm.io/gen. DO NOT EDIT.

package model

import (
	"time"
)

const TableNameOrder = "order"

// Order mapped from table <order>
type Order struct {
	CreatedDate      *time.Time `gorm:"column:created_date;type:timestamp with time zone;default:now()" json:"created_date"`
	UpdatedDate      *time.Time `gorm:"column:updated_date;type:timestamp with time zone" json:"updated_date"`
	CreatedBy        *string    `gorm:"column:created_by;type:text" json:"created_by"`
	UpdatedBy        *string    `gorm:"column:updated_by;type:text" json:"updated_by"`
	ID               string     `gorm:"column:id;type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	TenantCustomerID string     `gorm:"column:tenant_customer_id;type:uuid;not null" json:"tenant_customer_id"`
	TypeID           string     `gorm:"column:type_id;type:uuid;not null" json:"type_id"`
	CustomerUserID   *string    `gorm:"column:customer_user_id;type:uuid" json:"customer_user_id"`
	PathID           string     `gorm:"column:path_id;type:uuid;not null;default:tc_id_from_name('order_status_path'::text, 'default'::text)" json:"path_id"`
	StatusID         string     `gorm:"column:status_id;type:uuid;not null;default:tc_id_from_name('order_status'::text, 'created'::text)" json:"status_id"`
	Metadata         *string    `gorm:"column:metadata;type:jsonb;default:{}" json:"metadata"`

	OrderItemTransferAwayDomain OrderItemTransferAwayDomain
	OrderItemUpdateHosting      OrderItemUpdateHosting
}

// TableName Order's table name
func (*Order) TableName() string {
	return TableNameOrder
}
