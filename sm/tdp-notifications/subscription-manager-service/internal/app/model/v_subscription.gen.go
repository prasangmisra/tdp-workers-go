package model

import (
	"github.com/jmoiron/sqlx/types"
	"github.com/lib/pq"
	"gorm.io/gorm"
	"time"
)

const TableNameVSubscription = "v_subscription"

// VSubscription mapped from table <v_subscription>
type VSubscription struct {
	ID                string          `gorm:"column:id;type:uuid" json:"id"`
	Description       *string         `gorm:"column:description;type:text" json:"description"`
	Metadata          *types.JSONText `gorm:"column:metadata;type:jsonb" json:"metadata"`
	Tags              pq.StringArray  `gorm:"column:tags;type:text[]" json:"tags"`
	CreatedDate       *time.Time      `gorm:"column:created_date;type:timestamp with time zone" json:"created_date"`
	UpdatedDate       *time.Time      `gorm:"column:updated_date;type:timestamp with time zone" json:"updated_date"`
	DeletedDate       *gorm.DeletedAt `gorm:"column:deleted_date;type:timestamp with time zone" json:"deleted_date"`
	Status            string          `gorm:"column:status;type:text" json:"status"`
	TenantID          string          `gorm:"column:tenant_id;type:uuid" json:"tenant_id"`
	TenantCustomerID  *string         `gorm:"column:tenant_customer_id;type:uuid" json:"tenant_customer_id"`
	NotificationEmail string          `gorm:"column:notification_email;type:mbox" json:"notification_email"`
	Notifications     pq.StringArray  `gorm:"column:notifications;type:text[]" json:"notifications"`
	Type              *string         `gorm:"column:type;type:text" json:"type"`
	WebhookURL        *string         `gorm:"column:webhook_url;type:text" json:"webhook_url"`
	SigningSecret     *string         `gorm:"column:signing_secret;type:text" json:"signing_secret"`
}

// TableName VSubscription's table name
func (*VSubscription) TableName() string {
	return TableNameVSubscription
}
