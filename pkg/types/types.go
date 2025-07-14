package types

import (
	"encoding/json"
	"fmt"
	"math"
	"regexp"
	"time"

	"github.com/golang/protobuf/ptypes/timestamp"
	"github.com/google/uuid"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"

	commonmessages "github.com/tucowsinc/tdp-messages-go/message/common"
	_ "github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension" // this is needed for MarshalJSON to work
)

const (
	RedeemRestoreReason = "Registrant error."
	RedeemStatement1    = `This registrar has not restored the
Registered Name
in order to assume the rights to use
or sell the Registered Name for itself or for any
third party.`
	RedeemStatement2 = `The information in this report is
true to best of this registrar's knowledge, and this
registrar acknowledges that intentionally supplying
false information in this report shall constitute an
incurable material breach of the
Registry-Registrar Agreement.`
)

// ErrorDetails is used to store error details in job result data
type ErrorDetails struct {
	EppCode *int32  `json:"epp_code"`
	Message *string `json:"message"`
}

// SetErrorDetails sets the error details for the job result data
func (jrd *JobResultData) SetErrorDetails(eppCode *int32, msg *string) {
	jrd.Error = &ErrorDetails{
		EppCode: eppCode,
		Message: msg,
	}
}

// JobResultData is used to update the result_data column
// in the job table
type JobResultData struct {
	Message proto.Message
	Error   *ErrorDetails `json:"error,omitempty"`
}

func (jrd *JobResultData) MarshalJSON() ([]byte, error) {
	if jrd.Message == nil {
		return json.Marshal(struct {
			Error *ErrorDetails `json:"error_details,omitempty"`
		}{
			Error: jrd.Error,
		})
	}

	// Marshal the protobuf message into a map
	messageJSON, err := protojson.Marshal(jrd.Message)
	if err != nil {
		return nil, err
	}

	var messageMap map[string]interface{}
	if err := json.Unmarshal(messageJSON, &messageMap); err != nil {
		return nil, err
	}

	// Add ErrorDetails if present
	if jrd.Error != nil {
		messageMap["error"] = jrd.Error
	}

	return json.Marshal(messageMap)
}

// Accreditation will be included inside data
type Accreditation struct {
	IsProxy              bool   `json:"is_proxy"`
	TenantId             string `json:"tenant_id"`
	TenantName           string `json:"tenant_name"`
	ProviderId           string `json:"provider_id"`
	ProviderName         string `json:"provider_name"`
	AccreditationId      string `json:"accreditation_id"`
	AccreditationName    string `json:"accreditation_name"`
	ProviderInstanceId   string `json:"provider_instance_id"`
	ProviderInstanceName string `json:"provider_instance_name"`
	RegistrarID          string `json:"registrar_id"`
}

type AccreditationTld struct {
	TldId                string `json:"tld_id"`
	IsProxy              bool   `json:"is_proxy"`
	TldName              string `json:"tld_name"`
	TenantId             string `json:"tenant_id"`
	IsDefault            bool   `json:"is_default"`
	CustomId             string `json:"customer_id"`
	ProviderId           string `json:"provider_id"`
	RegistryId           string `json:"registry_id"`
	TenantName           string `json:"tenant_name"`
	CustomerName         string `json:"customer_name"`
	ProviderName         string `json:"provider_name"`
	RegistryName         string `json:"registry_name"`
	AccreditationId      string `json:"accreditation_id"`
	AccreditationName    string `json:"accreditation_name"`
	TenantCustomerId     string `json:"tenant_customer_id"`
	AccreditationTldId   string `json:"accreditation_tld_id"`
	ProviderInstanceId   string `json:"provider_instance_id"`
	ProviderInstanceName string `json:"provider_instance_name"`
	TenantCustomerNumber string `json:"tenant_customer_number"`
}

type OrderPrice struct {
	Currency string  `json:"currency"`
	Amount   float64 `json:"amount"`
	Fraction int32   `json:"fraction"`
}

// TimestampToTime converts protobuf timestamp into time.Time or nil if timestamp contains zero value
func TimestampToTime(timestamp *timestamppb.Timestamp) *time.Time {
	if timestamp == nil {
		return nil
	}

	t := timestamp.AsTime()
	return &t
}

// ExtractDomainName extracts domain name from given input
func ExtractDomainName(input string) string {
	domainRegex := regexp.MustCompile(`(?:^|\s)'?([a-z0-9\-]+(?:\.[a-z0-9\-]+)+)'?(?:$|\s)`)

	match := domainRegex.FindStringSubmatch(input)

	if len(match) >= 2 {
		return match[1]
	}

	return ""
}

type Metadata struct {
	TraceParent any    `json:"traceparent"`
	TraceState  any    `json:"tracestate"`
	OrderId     string `json:"order_id"`
}

type JobEvent struct {
	JobId          string   `json:"job_id"`
	Type           string   `json:"type"`
	Status         string   `json:"status"`
	ReferenceId    string   `json:"reference_id"`
	ReferenceTable string   `json:"reference_table"`
	RoutingKey     string   `json:"routing_key"`
	Metadata       Metadata `json:"metadata"`
}

func GetQueryQueue(accreditation string) (queue string) {
	queue = fmt.Sprintf("ry-%v-query", accreditation)
	return
}

func GetTransformQueue(accreditation string) (queue string) {
	queue = fmt.Sprintf("ry-%v-transform", accreditation)
	return
}

func SafeDeref[T any](p *T) T {
	if p == nil {
		var v T
		return v
	}
	return *p
}

// ToPointer returns a pointer to that value
func ToPointer[T any](s T) *T {
	return &s
}

// ParseJSON is a generic function to parse a JSON byte into the provided type.
func ParseJSON[T any](data []byte) (*T, error) {
	result := new(T)
	err := json.Unmarshal(data, result)
	return result, err
}

// ToTimestampMsg converts a time.Time to timestamp.Timestamp.
func ToTimestampMsg(t *time.Time) *timestamp.Timestamp {
	if t == nil {
		return nil
	}
	return timestamppb.New(*t)
}

// ToMoneyMsg converts a OrderPrice to common.Money.
func ToMoneyMsg(p *OrderPrice) *commonmessages.Money {
	price := p.Amount / float64(p.Fraction)

	// Extract price units
	priceUnits := int64(math.Floor(price))

	// Extract price nanos
	priceNanos := int32(math.Round((price - float64(priceUnits)) * 1e9))

	// Final price msg
	return &commonmessages.Money{CurrencyCode: p.Currency, Units: priceUnits, Nanos: priceNanos}
}

// AddMoney adds two Money values together
func AddMoney(a, b *commonmessages.Money) (*commonmessages.Money, error) {

	if a == nil || b == nil {
		return nil, fmt.Errorf("cannot add nil Money values")
	}

	// Check currency codes match
	if a.CurrencyCode != b.CurrencyCode {
		return nil, fmt.Errorf("cannot add different currencies: %s and %s",
			a.CurrencyCode, b.CurrencyCode)
	}

	totalNanos := a.Nanos + b.Nanos

	// Normalize nanos to be within valid range (-999,999,999 to +999,999,999)
	extraUnits := int64(totalNanos / 1_000_000_000)
	totalNanos = totalNanos % 1_000_000_000

	// Add units, including any overflow from nanos
	totalUnits := a.Units + b.Units + extraUnits

	return &commonmessages.Money{
		CurrencyCode: a.CurrencyCode,
		Units:        totalUnits,
		Nanos:        totalNanos,
	}, nil
}

func IsValidUUID(u string) bool {
	_, err := uuid.Parse(u)
	return err == nil
}

var JobStatus = struct {
	Created,
	Submitted,
	Processing,
	Completed,
	Failed,
	CompletedConditionally string
}{
	"created",
	"submitted",
	"processing",
	"completed",
	"failed",
	"completed_conditionally",
}

var PollMessageStatus = struct {
	Pending,
	Submitted,
	Processed,
	Failed string
}{
	"pending",
	"submitted",
	"processed",
	"failed",
}

var ProvisionStatus = struct {
	Pending,
	Processing,
	Completed,
	Failed,
	PendingAction string
}{
	"pending",
	"processing",
	"completed",
	"failed",
	"pending_action",
}

var TransferStatus = struct {
	ClientApproved,
	ClientCancelled,
	ClientRejected,
	Pending,
	ServerApproved,
	ServerCancelled string
}{
	"clientApproved",
	"clientCancelled",
	"clientRejected",
	"pending",
	"serverApproved",
	"serverCancelled",
}

var OrderItemPlanStatus = struct {
	New,
	Ready,
	Processing,
	Completed,
	Failed string
}{
	"new",
	"ready",
	"processing",
	"completed",
	"failed",
}

var OrderItemPlanValidationStatus = struct {
	Pending,
	Started,
	Completed,
	Failed string
}{
	"pending",
	"started",
	"completed",
	"failed",
}

var EppCode = struct {
	Success,
	Pending,
	Exists,
	NotPendingTransfer,
	ObjectDoesNotExist,
	InvalidAuthInfo,
	ParameterPolicyError,
	ObjectAssociationProhibitsOperation,
	CommandFailed int32
}{
	1000,
	1001,
	2302,
	2301,
	2303,
	2202,
	2306,
	2305,
	2400,
}

var EPPStatusCode = struct {
	AddPeriod,
	AutoRenewPeriod,
	Inactive,
	Ok,
	PendingCreate,
	PendingDelete,
	PendingRenew,
	PendingRestore,
	PendingTransfer,
	PendingUpdate,
	RedemptionPeriod,
	RenewPeriod,
	ServerDeleteProhibited,
	ServerHold,
	ServerRenewProhibited,
	ServerTransferProhibited,
	ServerUpdateProhibited,
	TransferPeriod,
	ClientDeleteProhibited,
	ClientHold,
	ClientRenewProhibited,
	ClientTransferProhibited,
	ClientUpdateProhibited string
}{
	"addPeriod",
	"autoRenewPeriod",
	"inactive",
	"ok",
	"pendingCreate",
	"pendingDelete",
	"pendingRenew",
	"pendingRestore",
	"pendingTransfer",
	"pendingUpdate",
	"redemptionPeriod",
	"renewPeriod",
	"serverDeleteProhibited",
	"serverHold",
	"serverRenewProhibited",
	"serverTransferProhibited",
	"serverUpdateProhibited",
	"transferPeriod",
	"clientDeleteProhibited",
	"clientHold",
	"clientRenewProhibited",
	"clientTransferProhibited",
	"clientUpdateProhibited",
}

var RgpStatus = struct {
	AddPeriod,
	AutoRenewPeriod,
	RenewPeriod,
	TransferPeriod,
	RedemptionPeriod,
	PendingRestore,
	PendingDelete string
}{
	"addPeriod",
	"autoRenewPeriod",
	"renewPeriod",
	"transferPeriod",
	"redemptionPeriod",
	"pendingRestore",
	"pendingDelete",
}

var OrderStatusEnum = struct {
	Created,
	Processing,
	Successful,
	Failed string
}{
	"created",
	"processing",
	"successful",
	"failed",
}

var DomainOrderType = struct {
	Create,
	Renew,
	Redeem,
	TransferIn string
}{
	"create",
	"renew",
	"redeem",
	"transfer_in",
}

// The list of order statuses in Hosting API: https://github.com/tucowsinc/tucows-domainshosting-app/blob/dev/cmd/functions/order/models/constants.go#L3
var OrderStatusHostingAPI = struct {
	Requested,
	InProgress,
	Completed,
	Failed string
}{
	"Requested",
	"In progress",
	"Completed",
	"Failed",
}

// LogFieldKeys defines standard keys for log fields across the project
var LogFieldKeys = struct {
	JobID                string
	JobType              string
	LogID                string
	Status               string
	Error                string
	Message              string
	MessageID            string
	MessageCorrelationID string
	Queue                string
	Config               string
	WorkerName           string
	ProductID            string
	Context              string
	CorrelationID        string
	EventID              string
	EppCode              string
	EppMessage           string
	XmlResponse          string
	Response             string
	Host                 string
	HostID               string
	Contact              string
	ContactID            string
	Hosting              string
	HostingID            string
	Domain               string
	DomainID             string
	OrderID              string
	Accreditation        string
	AccreditationID      string
	Tenant               string
	TenantID             string
	RequestID            string
	CronType             string
	ProvisionID          string
	Provision            string
	Metadata             string
}{
	JobID:                "job_id",
	JobType:              "job_type",
	LogID:                "log_id",
	Status:               "status",
	Error:                "error",
	Message:              "message",
	MessageID:            "msg_id",
	MessageCorrelationID: "msg_correlation_id",
	Queue:                "queue",
	Config:               "config",
	WorkerName:           "worker_name",
	ProductID:            "product_id",
	Context:              "context",
	CorrelationID:        "correlation_id",
	EventID:              "event_id",
	EppCode:              "epp_code",
	EppMessage:           "epp_message",
	XmlResponse:          "xml_response",
	Response:             "response",
	Host:                 "host",
	HostID:               "host_id",
	Contact:              "contact",
	ContactID:            "contact_id",
	Hosting:              "hosting",
	HostingID:            "hosting_id",
	Domain:               "domain",
	DomainID:             "domain_id",
	OrderID:              "order_id",
	Accreditation:        "accreditation",
	AccreditationID:      "accreditation_id",
	Tenant:               "tenant",
	TenantID:             "tenant_id",
	RequestID:            "request_id",
	CronType:             "cron_type",
	ProvisionID:          "provision_id",
	Provision:            "provision",
	Metadata:             "metadata",
}

var LogMessages = struct {
	ConfigurationLoadFailed             string
	ConfigurationLoaded                 string
	StartingDatadogTracer               string
	TracerDisabled                      string
	MessageBusSetupFailed               string
	MessageBusSetupSuccess              string
	DatabaseConnectionFailed            string
	DatabaseConnectionSuccess           string
	ConsumingQueuesStarted              string
	ConsumingQueuesFailed               string
	WorkerTerminated                    string
	ReceivedResponseFromCertBE          string
	ReceivedRenewResponseFromCertBE     string
	ReceivedResponseFromRY              string
	FetchJobByIDFromDBFailed            string
	FetchJobByEventIDFromDBFailed       string
	FetchJobFromDBSuccess               string
	UnexpectedJobStatus                 string
	JSONDecodeFailed                    string
	ParseJobDataToRegistryRequestFailed string
	MessageSendingToBusFailed           string
	MessageSendingToBusSuccess          string
	UpdateStatusInDBFailed              string
	UpdateStatusInDBSuccess             string
	HandleMessageFailed                 string
	JobProcessingCompleted              string
}{
	ConfigurationLoadFailed:             "Unable to load required configuration",
	ConfigurationLoaded:                 "Configuration successfully loaded",
	StartingDatadogTracer:               "Starting DataDog tracer...",
	TracerDisabled:                      "Tracer instantiation is disabled.",
	MessageBusSetupFailed:               "Error creating messagebus instance",
	MessageBusSetupSuccess:              "Messagebus instance created successfully",
	DatabaseConnectionFailed:            "Failed to create database connection",
	DatabaseConnectionSuccess:           "Database connection established successfully",
	ConsumingQueuesStarted:              "Starting consuming from queues",
	ConsumingQueuesFailed:               "Error on consuming from queues",
	WorkerTerminated:                    "Worker terminated",
	ReceivedResponseFromCertBE:          "Certificate issued notification received from cert backend",
	ReceivedRenewResponseFromCertBE:     "Certificate renew notification received from cert backend",
	ReceivedResponseFromRY:              "Received response from RY interface",
	FetchJobByIDFromDBFailed:            "Error fetching job by ID from database",
	FetchJobByEventIDFromDBFailed:       "Error fetching job by event_id from database",
	FetchJobFromDBSuccess:               "Fetched job from database",
	UnexpectedJobStatus:                 "Unexpected job status, skipping processing",
	JSONDecodeFailed:                    "Failed to decode job JSON data",
	ParseJobDataToRegistryRequestFailed: "Failed to parse job data to registry request",
	MessageSendingToBusFailed:           "Error sending message to bus",
	MessageSendingToBusSuccess:          "Successfully sent message to bus",
	UpdateStatusInDBFailed:              "Failed to update job status in database",
	UpdateStatusInDBSuccess:             "Job status updated in database successfully",
	HandleMessageFailed:                 "Failed to handle message",
	JobProcessingCompleted:              "Job processing completed",
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

var NotificationType = struct {
	DomainTransfer string
}{
	"domain.transfer",
}
