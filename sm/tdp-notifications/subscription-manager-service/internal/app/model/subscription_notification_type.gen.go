package model

const TableNameSubscriptionNotificationType = "subscription_notification_type"

// SubscriptionNotificationType mapped from table <subscription_notification_type>
type SubscriptionNotificationType struct {
	ID             string `gorm:"column:id;type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	SubscriptionID string `gorm:"column:subscription_id;type:uuid;not null" json:"subscription_id"`
	TypeID         string `gorm:"column:type_id;type:uuid;not null" json:"type_id"`
}

// TableName SubscriptionNotificationType's table name
func (*SubscriptionNotificationType) TableName() string {
	return TableNameSubscriptionNotificationType
}
