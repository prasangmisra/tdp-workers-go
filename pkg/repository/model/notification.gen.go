package model

import (
	"time"

	"github.com/jmoiron/sqlx/types"
)

const TableNameNotification = "notification"

// Notification mapped from table <notification>
type Notification struct {
	CreatedDate      *time.Time      `gorm:"column:created_date;type:timestamp with time zone;default:now()" json:"created_date"`
	UpdatedDate      *time.Time      `gorm:"column:updated_date;type:timestamp with time zone" json:"updated_date"`
	CreatedBy        *string         `gorm:"column:created_by;type:text;default:CURRENT_USER" json:"created_by"`
	UpdatedBy        *string         `gorm:"column:updated_by;type:text" json:"updated_by"`
	DeletedDate      *time.Time      `gorm:"column:deleted_date;type:timestamp with time zone" json:"deleted_date"`
	DeletedBy        *string         `gorm:"column:deleted_by;type:text" json:"deleted_by"`
	ID               string          `gorm:"column:id;type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	TypeID           string          `gorm:"column:type_id;type:uuid;not null" json:"type_id"`
	Payload          *types.JSONText `gorm:"column:payload;type:jsonb;not null" json:"payload"`
	TenantID         string          `gorm:"column:tenant_id;type:uuid;not null" json:"tenant_id"`
	TenantCustomerID *string         `gorm:"column:tenant_customer_id;type:uuid" json:"tenant_customer_id"`
}

// TableName Notification's table name
func (*Notification) TableName() string {
	return TableNameNotification
}
