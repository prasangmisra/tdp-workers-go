// Code generated by gorm.io/gen. DO NOT EDIT.
// Code generated by gorm.io/gen. DO NOT EDIT.
// Code generated by gorm.io/gen. DO NOT EDIT.

package model

import (
	"github.com/jmoiron/sqlx/types"
	"time"
)

const TableNamePollMessage = "poll_message"

// PollMessage mapped from table <poll_message>
// This code taken from:  https://github.com/tucowsinc/tdp-workers-go/tree/develop/pkg/database/model
// Used only for the enqueuer's Config tests.  Has no application use.
type PollMessage struct {
	ID                string          `gorm:"column:id;type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	Accreditation     string          `gorm:"column:accreditation;type:text;not null" json:"accreditation"`
	EppMessageID      string          `gorm:"column:epp_message_id;type:text;not null" json:"epp_message_id"`
	Msg               *string         `gorm:"column:msg;type:text" json:"msg"`
	Lang              *string         `gorm:"column:lang;type:text" json:"lang"`
	TypeID            string          `gorm:"column:type_id;type:uuid;not null" json:"type_id"`
	StatusID          string          `gorm:"column:status_id;type:uuid;not null;default:tc_id_from_name('poll_message_status'::text, 'pending'::text)" json:"status_id"`
	Data              *types.JSONText `gorm:"column:data;type:jsonb" json:"data"`
	QueueDate         *time.Time      `gorm:"column:queue_date;type:timestamp with time zone" json:"queue_date"`
	CreatedDate       *time.Time      `gorm:"column:created_date;type:timestamp with time zone;default:now()" json:"created_date"`
	LastSubmittedDate *time.Time      `gorm:"column:last_submitted_date;type:timestamp with time zone" json:"last_submitted_date"`
}

// TableName PollMessage's table name
func (*PollMessage) TableName() string {
	return TableNamePollMessage
}

func (p *PollMessage) GetID() string {
	return p.ID
}
