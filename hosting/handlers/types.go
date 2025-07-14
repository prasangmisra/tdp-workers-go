package handlers

import (
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/alexliesenfeld/health"
	"github.com/go-resty/resty/v2"
	"github.com/jarcoal/httpmock"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-shared-go/dns"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	mb "github.com/tucowsinc/tdp-workers-go/pkg/message_bus"
)

var errorMessages = map[string]string{
	http.MethodPatch:  "error sending patch command",
	http.MethodGet:    "error sending get command",
	http.MethodDelete: "error sending delete command",
	http.MethodPost:   "error sending post command",
}

var (
	ErrorCertificateExists = errors.New("certificate already exists for this domain")
	ErrorClientTimeout     = errors.New("client timed out waiting for response")
)

type WorkerService struct {
	db                  database.Database
	bus                 messagebus.MessageBus
	hostingApi          *hostingApi
	certificateApi      *certificateApi
	ACMEChallengeDomain string
	CertBotApiTimeout   time.Duration
	resolver            dns.IDnsResolver
}

// NewWorkerService creates a new instance of WorkerService and configures
// the database and http client used to communicate with the external api
func NewWorkerService(bus messagebus.MessageBus, db database.Database, resolver dns.IDnsResolver, cfg config.Config) *WorkerService {
	return &WorkerService{
		db:  db,
		bus: bus,
		hostingApi: &hostingApi{
			client: resty.New().
				SetDebug(false). // enabling debug will print the request/response body and url that contains certificate private key, hosting client name and email
				SetRetryCount(cfg.GetAPIRetryCount()).
				SetRetryWaitTime(cfg.GetAPIMinWaitTime()).
				SetRetryMaxWaitTime(cfg.GetAPIMaxWaitTime()).
				AddRetryCondition(func(response *resty.Response, err error) bool {
					return response.StatusCode() == http.StatusRequestTimeout ||
						response.StatusCode() >= http.StatusInternalServerError
				}),
			cfg: cfg,
		},
		certificateApi: &certificateApi{
			client: resty.New().
				SetDebug(false). // enabling debug will print the request body that contains certificate private key
				SetRetryCount(cfg.GetAPIRetryCount()).
				SetRetryWaitTime(cfg.GetAPIMinWaitTime()).
				SetRetryMaxWaitTime(cfg.GetAPIMaxWaitTime()).
				AddRetryCondition(func(response *resty.Response, err error) bool {
					return response.StatusCode() == http.StatusRequestTimeout ||
						response.StatusCode() >= http.StatusInternalServerError
				}),
			cfg: cfg,
		},
		ACMEChallengeDomain: cfg.HostingCNAMEDomain,
		CertBotApiTimeout:   cfg.GetCertBotApiTimeout(),
		resolver:            resolver,
	}
}

// RegisterHandlers registers the handlers for the service.
func (s *WorkerService) RegisterHandlers() {
	// notifications from database
	s.bus.Register(
		&job.Notification{},
		s.HandlerRouter,
	)
}

// HealthChecks returns a slice of health checks for the service.
func (s *WorkerService) HealthChecks(cfg config.Config) (checks []health.Check) {
	return []health.Check{
		database.HealthCheck(s.db),
		mb.HealthCheck(cfg.RmqUrl()),
	}
}

// CreateOrderRequest represents the request to create a new order (static and dynamic) with the web hosting backend.
// The response returned by CreateOrderRequest is of type OrderResponse
type CreateOrderRequest struct {
	ClientId    string             `json:"clientId"`
	ProductId   string             `json:"productId"`
	Domain      DomainDetails      `json:"domain"`
	Components  *ComponentsDetails `json:"components,omitempty"`
	AwsRegionId string             `json:"awsRegionId"`
}

// UpdateOrderRequest represents the request to update an existing order with the hosting backend.
// The response returned by UpdateOrderRequest is of type OrderResponse
type UpdateOrderRequest struct {
	orderId  string
	IsActive bool `json:"isActive"`
}

// UpdateCertificateRequest represents the request to update the ssl certificate on an existing order with the hosting backend.
// This request does not return any response
type UpdateCertificateRequest struct {
	orderId string
	CertificateDetails
}

// DeleteOrderRequest represents the request to delete an existing order with the hosting backend.
// The response returned by DeleteOrderRequest is of type OrderResponse
type DeleteOrderRequest struct {
	orderId string
}

// CreateClientRequest represents the request to create a new client with the hosting backend.
// The response returned by CreateClientRequest is of type ClientResponse
type CreateClientRequest struct {
	ClientDetails
	Password string `json:"password"`
}

// UpdateClientRequest represents the request to update an existing client with the hosting backend.
// The response returned by the UpdateClientRequest is of type ClientResponse
type UpdateClientRequest struct {
	ClientDetails
	Password string `json:"password"`
	IsActive string `json:"isActive"`
}

// CreateResellerRequest represents the request to create reseller with the hosting backend
type CreateResellerRequest struct {
	ResellerDetails
}

type OrderResponse struct {
	Id           string    `json:"id"`
	ProductId    string    `json:"productId"`
	ProductName  string    `json:"productName"`
	ClientId     string    `json:"clientId"`
	ClientName   string    `json:"clientName"`
	DomainName   string    `json:"domainName"`
	AwsAccountId string    `json:"awsAccountId"`
	AwsRegionId  string    `json:"awsRegionId"`
	Status       string    `json:"status"`
	IsActive     bool      `json:"isActive"`
	IsDeleted    bool      `json:"isDeleted"`
	CreatedAt    time.Time `json:"createdAt"`
	UpdatedAt    time.Time `json:"updatedAt"`
}

type ClientResponse struct {
	Id        string    `json:"id"`
	Username  string    `json:"username"`
	IsActive  bool      `json:"isActive"`
	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`
	ClientDetails
}

type ResellerResponse struct {
	Id        string     `json:"id"`
	IsActive  bool       `json:"is_active"`
	CreatedAt time.Time  `json:"created_at"`
	UpdatedAt *time.Time `json:"updated_at"`
	ResellerDetails
}

type AWSRegionResponse struct {
	Id       string `json:"id"`
	IsActive bool   `json:"is_active"`
	Location string `json:"location"`
	Name     string `json:"name"`
	Region   string `json:"region"`
}

type CertificateDetails struct {
	Body       string `json:"body"`
	Chain      string `json:"chain"`
	PrivateKey string `json:"privateKey"`
}

type ComponentsDetails struct {
	Containers []ContainerDetails `json:"containers,omitempty"`
	Database   *DatabaseDetails   `json:"database,omitempty"`
}

type ContainerDetails struct {
	Name string `json:"componentName"`
}

type DatabaseDetails struct {
	Name string `json:"componentName"`
}

type DomainDetails struct {
	Name        string              `json:"name"`
	Certificate *CertificateDetails `json:"certificate,omitempty"`
}

type ProductDetails struct {
	VersionId        string  `json:"productVersionId"`
	Replicas         float64 `json:"replicas"`
	StorageSize      float64 `json:"storageSize"`
	DatabaseName     string  `json:"databaseName"`
	DatabaseUserName string  `json:"databaseUser"`
	DatabasePassword string  `json:"databasePassword"`
}

type ClientDetails struct {
	Name         string `json:"name"`
	Email        string `json:"email"`
	ResellerName string `json:"resellerName"`
}

type ResellerDetails struct {
	Name  string `json:"name"`
	Email string `json:"email"`
}

type CreateCertificateRequest struct {
	Domain    string `json:"domain"`
	RequestId string `json:"requestid"`
}

type CreateCertificateResponse struct {
	DomainName string `json:"domain"`
	Message    string `json:"message"`
	Status     string `json:"status"`
}

type GetCertificateStatusResponse struct {
	DomainName string `json:"domain"`
	Message    string `json:"message"`
	Status     string `json:"status"`
}

type GetCertificateResponse struct {
	Cert      string `json:"cert"`
	Chain     string `json:"chain"`
	Domain    string `json:"domain"`
	Fullchain string `json:"fullchain"`
	Privkey   string `json:"privkey"`
}

type CertificateErrorDetails struct {
	Error string `json:"error"`
}

// ErrorDetails represents the response returned by the hosting backend in case of an un-successful request
type ErrorDetails struct {
	Message string `json:"message"`
}

// EmptyResponse represents a struct for scenarios where the api does not return a response body
type EmptyResponse struct{}

// createOrderRequest creates a new CreateOrderRequest from types.HostingData
func createOrderRequest(data *types.HostingData) CreateOrderRequest {
	request := CreateOrderRequest{
		ClientId:  *data.Client.ExternalClientId,
		ProductId: data.ProductId,
		Domain: DomainDetails{
			Name: data.DomainName,
		},
		AwsRegionId: data.RegionId,
	}

	if data.Certificate != nil {
		request.Domain.Certificate = &CertificateDetails{
			Body:       data.Certificate.Body,
			PrivateKey: data.Certificate.PrivateKey,
			Chain:      data.Certificate.Chain,
		}

	}

	if data.Components != nil {
		var components ComponentsDetails

		for _, c := range data.Components {
			switch c.Type {
			case "container":
				components.Containers = append(components.Containers, ContainerDetails{
					Name: c.Name,
				})
			case "database":
				components.Database = &DatabaseDetails{Name: c.Name}
			default:
				log.Warn("unknown component type received", log.Fields{"type": c.Type})
			}
		}

		request.Components = &components
	}

	return request
}

// createClientRequest creates a new CreateClientRequest from types.HostingData
func createClientRequest(data *types.HostingData) CreateClientRequest {
	return CreateClientRequest{
		ClientDetails: ClientDetails{
			Name:         data.Client.Name,
			ResellerName: data.CustomerName,
			Email:        data.Client.Email,
		},
		Password: data.Client.Password,
	}
}

// createUpdateOrderRequest creates a new UpdateOrderRequest from types.HostingUpdateData
func createUpdateOrderRequest(data *types.HostingUpdateData) UpdateOrderRequest {
	return UpdateOrderRequest{
		IsActive: *data.IsActive,
		orderId:  data.ExternalOrderId,
	}
}

// createUpdateCertificateRequest creates a new UpdateCertificateRequest from types.HostingUpdateData
func createUpdateCertificateRequest(data *types.HostingUpdateData) UpdateCertificateRequest {
	return UpdateCertificateRequest{
		orderId: data.ExternalOrderId,
		CertificateDetails: CertificateDetails{
			Body:       data.Certificate.Body,
			Chain:      data.Certificate.Chain,
			PrivateKey: data.Certificate.PrivateKey,
		},
	}
}

// createDeleteOrderRequest creates a new DeleteOrderRequest from types.HostingDeleteData
func createDeleteOrderRequest(data *types.HostingDeleteData) DeleteOrderRequest {
	return DeleteOrderRequest{
		orderId: data.ExternalOrderId,
	}
}

// createResellerRequest creates a new CreateReseller Request from types.HostingData
func createResellerRequest(data *types.HostingData) CreateResellerRequest {
	return CreateResellerRequest{
		ResellerDetails: ResellerDetails{
			Name:  data.CustomerName,
			Email: data.CustomerEmail,
		},
	}
}

// toSlice converts an interface to an interface slice without using reflection
func toSlice[T interface{}](i interface{}) (slice []T, err error) {
	switch t := i.(type) {
	case []T:
		for x := 0; x < len(t); x++ {
			slice = append(slice, t[x])
		}
	default:
		err = fmt.Errorf("invalid type: %v", t)
	}

	return slice, err
}

// processHostingResponse processes the response returned by hosting backend. If the response is successful
// it returns TResponse, otherwise returns the error response returned formatted as error
func processHostingResponse[TResponse interface{}](r *resty.Response) (response *TResponse, err error) {
	if r.IsSuccess() {
		response = r.Result().(*TResponse)
		return
	}

	errorResponse := r.Error().(*ErrorDetails)
	err = fmt.Errorf("%s: %s", errorMessages[r.Request.Method], errorResponse.Message)
	return
}

func processCertificateResponse[TResponse interface{}](r *resty.Response) (response *TResponse, err error) {
	if r.IsSuccess() {
		response = r.Result().(*TResponse)
		return
	}

	errorResponse := r.Error().(*CertificateErrorDetails)

	switch {
	case strings.Contains(errorResponse.Error, "domain already processed"):
		err = ErrorCertificateExists
	default:
		err = fmt.Errorf("%s: %s", errorMessages[r.Request.Method], errorResponse.Error)
	}
	return
}

func setupMockResponder(httpStatus int, content string) httpmock.Responder {
	resp := httpmock.NewStringResponse(httpStatus, content)
	resp.Header.Set("Content-Type", "application/json")

	return httpmock.ResponderFromResponse(resp)
}

func setupMockErrorResponder(err error) httpmock.Responder {
	return httpmock.NewErrorResponder(err)
}
