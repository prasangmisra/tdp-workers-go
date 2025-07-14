package model

import (
	"github.com/jmoiron/sqlx/types"
	"github.com/lib/pq"
	"gorm.io/gorm"
	"time"
)

const TableNameSubscription = "subscription"

// Subscription mapped from table <subscription>
type Subscription struct {
	CreatedDate *time.Time      `gorm:"column:created_date;type:timestamp with time zone;default:now()" json:"created_date"`
	UpdatedDate *time.Time      `gorm:"column:updated_date;type:timestamp with time zone" json:"updated_date"`
	CreatedBy   *string         `gorm:"column:created_by;type:text;->" json:"created_by"`
	UpdatedBy   *string         `gorm:"column:updated_by;type:text" json:"updated_by"`
	DeletedDate *gorm.DeletedAt `gorm:"column:deleted_date;type:timestamp with time zone" json:"deleted_date"`
	DeletedBy   *string         `gorm:"column:deleted_by;type:text" json:"deleted_by"`

	ID                string          `gorm:"column:id;type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	Descr             *string         `gorm:"column:descr;type:text" json:"descr"`
	StatusID          string          `gorm:"column:status_id;type:uuid;not null;<-:update" json:"status_id"`
	TenantID          string          `gorm:"column:tenant_id;type:uuid;not null" json:"tenant_id"`
	TenantCustomerID  *string         `gorm:"column:tenant_customer_id;type:uuid" json:"tenant_customer_id"`
	NotificationEmail string          `gorm:"column:notification_email;type:mbox;not null" json:"notification_email"`
	Metadata          *types.JSONText `gorm:"column:metadata;type:jsonb" json:"metadata"`
	Tags              pq.StringArray  `gorm:"column:tags;type:text[]" json:"tags"`
}

// TableName Subscription's table name
func (*Subscription) TableName() string {
	return TableNameSubscription
}
