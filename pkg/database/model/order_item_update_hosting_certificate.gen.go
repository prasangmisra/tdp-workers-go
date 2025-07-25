// Code generated by gorm.io/gen. DO NOT EDIT.
// Code generated by gorm.io/gen. DO NOT EDIT.
// Code generated by gorm.io/gen. DO NOT EDIT.

package model

import (
	"time"
)

const TableNameOrderItemUpdateHostingCertificate = "order_item_update_hosting_certificate"

// OrderItemUpdateHostingCertificate mapped from table <order_item_update_hosting_certificate>
type OrderItemUpdateHostingCertificate struct {
	CreatedDate *time.Time `gorm:"column:created_date;type:timestamp with time zone;default:now()" json:"created_date"`
	UpdatedDate *time.Time `gorm:"column:updated_date;type:timestamp with time zone" json:"updated_date"`
	CreatedBy   *string    `gorm:"column:created_by;type:text;default:CURRENT_USER" json:"created_by"`
	UpdatedBy   *string    `gorm:"column:updated_by;type:text" json:"updated_by"`
	ID          string     `gorm:"column:id;type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	Body        string     `gorm:"column:body;type:text;not null" json:"body"`
	Chain       *string    `gorm:"column:chain;type:text" json:"chain"`
	PrivateKey  string     `gorm:"column:private_key;type:text;not null" json:"private_key"`
	NotBefore   time.Time  `gorm:"column:not_before;type:timestamp with time zone;not null" json:"not_before"`
	NotAfter    time.Time  `gorm:"column:not_after;type:timestamp with time zone;not null" json:"not_after"`
}

// TableName OrderItemUpdateHostingCertificate's table name
func (*OrderItemUpdateHostingCertificate) TableName() string {
	return TableNameOrderItemUpdateHostingCertificate
}
