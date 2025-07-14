package model

const TableNameNotificationType = "notification_type"

// NotificationType mapped from table <notification_type>
type NotificationType struct {
	ID    string  `gorm:"column:id;type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	Name  string  `gorm:"column:name;type:text;not null" json:"name"`
	Descr *string `gorm:"column:descr;type:text" json:"descr"`
}

// TableName NotificationType's table name
func (*NotificationType) TableName() string {
	return TableNameNotificationType
}

// GetID NotificationType id
func (nt *NotificationType) GetID() string {
	return nt.ID
}

// GetName NotificationType name
func (nt *NotificationType) GetName() string {
	return nt.Name
}
