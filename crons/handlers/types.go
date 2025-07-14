package handlers

import "time"

var CronServiceTypeNameEnum = struct {
	TransferInCron,
	TransferAwayCron,
	DomainPurgeCron,
	EventEnqueueCron string
}{
	"transfer-in-cron",
	"transfer-away-cron",
	"domain-purge-cron",
	"event-enqueue-cron",
}

type DomainTransferEvent struct {
	Name          *string    `json:"name"`
	Status        *string    `json:"status"`
	ActionBy      *string    `json:"actionBy"`
	ActionDate    *time.Time `json:"actionDate"`
	RequestedBy   *string    `json:"requestedBy"`
	RequestedDate *time.Time `json:"requestedDate"`
	ExpiryDate    *time.Time `json:"expiryDate"`
}
