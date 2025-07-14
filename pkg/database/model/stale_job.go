package model

type StaleJob struct {
	JobID         string
	JobStatusName string
	NotifyEvent   bool
}
