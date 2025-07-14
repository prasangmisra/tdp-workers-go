package types

import (
	_ "github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension" // this is needed for MarshalJSON to work
)

// This code taken from:  https://github.com/tucowsinc/tdp-workers-go/tree/develop/pkg/database/model

// LogFieldKeys defines standard keys for log fields across the project
var LogFieldKeys = struct {
	Error string
}{
	Error: "error",
}

var LogMessages = struct {
	ConfigurationLoadFailed         string
	ConfigurationLoaded             string
	StartingDatadogTracer           string
	TracerDisabled                  string
	MessageBusSetupFailed           string
	MessageBusSetupSuccess          string
	DatabaseConnectionFailed        string
	DatabaseConnectionSuccess       string
	ConsumingQueuesStarted          string
	ConsumingQueuesFailed           string
	ReceivedResponseFromCertBE      string
	ReceivedRenewResponseFromCertBE string
	JSONDecodeFailed                string
	MessageSendingToBusFailed       string
	MessageSendingToBusSuccess      string
	HandleMessageFailed             string
	JobProcessingCompleted          string
}{
	ConfigurationLoadFailed:         "Unable to load required configuration",
	ConfigurationLoaded:             "Configuration successfully loaded",
	StartingDatadogTracer:           "Starting DataDog tracer...",
	TracerDisabled:                  "Tracer instantiation is disabled.",
	MessageBusSetupFailed:           "Error creating messagebus instance",
	MessageBusSetupSuccess:          "Messagebus instance created successfully",
	DatabaseConnectionFailed:        "Failed to create database connection",
	DatabaseConnectionSuccess:       "Database connection established successfully",
	ConsumingQueuesStarted:          "Starting consuming from queues",
	ConsumingQueuesFailed:           "Error on consuming from queues",
	ReceivedResponseFromCertBE:      "Certificate issued notification received from cert backend",
	ReceivedRenewResponseFromCertBE: "Certificate renew notification received from cert backend",
	JSONDecodeFailed:                "Failed to decode job JSON data",
	MessageSendingToBusFailed:       "Error sending message to bus",
	MessageSendingToBusSuccess:      "Successfully sent message to bus",
	HandleMessageFailed:             "Failed to handle message",
	JobProcessingCompleted:          "Job processing completed",
}

type OrderByDirection int

const (
	OrderByDirectionAsc OrderByDirection = iota
	OrderByDirectionDesc
)

func (d OrderByDirection) String() string {
	switch d {
	case OrderByDirectionAsc:
		return "ASC"
	case OrderByDirectionDesc:
		return "DESC"
	default:
		return "ASC"
	}
}

// ToPointer returns a pointer to that value
func ToPointer[T any](s T) *T {
	return &s
}

func PointerToValue[T any](s *T) T {
	if s == nil {
		var zero T
		return zero
	}
	return *s
}
