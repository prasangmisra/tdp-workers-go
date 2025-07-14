package model

const TableNameSubscriptionStatus = "subscription_status"

// SubscriptionStatus mapped from table <subscription_status>
type SubscriptionStatus struct {
	ID    string  `gorm:"column:id;type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	Name  string  `gorm:"column:name;type:text;not null" json:"name"`
	Descr *string `gorm:"column:descr;type:text" json:"descr"`
}

// TableName SubscriptionStatus's table name
func (*SubscriptionStatus) TableName() string {
	return TableNameSubscriptionStatus
}

// GetID NotificationType id
func (ss *SubscriptionStatus) GetID() string {
	return ss.ID
}

// GetName NotificationType name
func (ss *SubscriptionStatus) GetName() string {
	return ss.Name
}
