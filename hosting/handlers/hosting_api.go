package handlers

import (
	"fmt"
	"net/http"

	"github.com/go-resty/resty/v2"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
)

var _ HostingApi = (*hostingApi)(nil)

const (
	ApiKeyHeaderName = "x-api-key"
)

// Swagger: https://github.com/tucowsinc/tucows-domainshosting-app/blob/dev/docs/api/api-spec.yaml
type HostingApi interface {
	CreateHosting(request CreateOrderRequest) (*OrderResponse, error)
	CreateClient(request CreateClientRequest) (*ClientResponse, error)
	UpdateHosting(request UpdateOrderRequest) (*OrderResponse, error)
	UpdateHostingCertificate(request UpdateCertificateRequest) error
	GetClientByEmail(email, resellerName string) (*ClientResponse, error)
}

type hostingApi struct {
	client *resty.Client
	cfg    config.Config
}

// CreateHosting creates a new hosting order
func (api *hostingApi) CreateHosting(request CreateOrderRequest) (response *OrderResponse, err error) {
	endpoint := fmt.Sprintf("%s/orders", api.cfg.AWSHostingApiBaseEndpoint)

	resp, err := api.client.R().
		SetHeader(ApiKeyHeaderName, api.cfg.AWSHostingApiKey).
		SetResult(&OrderResponse{}).
		SetError(&ErrorDetails{}).
		SetBody(request).
		Post(endpoint)

	if err == nil {
		response, err = processHostingResponse[OrderResponse](resp)
	}

	return
}

// UpdateHosting updates an existing hosting order
func (api *hostingApi) UpdateHosting(request UpdateOrderRequest) (response *OrderResponse, err error) {
	endpoint := fmt.Sprintf("%s/orders/{orderId}", api.cfg.AWSHostingApiBaseEndpoint)

	resp, err := api.client.R().
		SetHeader(ApiKeyHeaderName, api.cfg.AWSHostingApiKey).
		SetPathParam("orderId", request.orderId).
		SetResult(&OrderResponse{}).
		SetError(&ErrorDetails{}).
		SetBody(request).
		Patch(endpoint)

	if err == nil {
		response, err = processHostingResponse[OrderResponse](resp)
	}

	return
}

// UpdateHostingCertificate updates the ssl certificate on an existing hosting order
func (api *hostingApi) UpdateHostingCertificate(request UpdateCertificateRequest) (err error) {
	endpoint := fmt.Sprintf("%s/orders/certificate/{orderId}", api.cfg.AWSHostingApiBaseEndpoint)

	resp, err := api.client.R().
		SetHeader(ApiKeyHeaderName, api.cfg.AWSHostingApiKey).
		SetPathParam("orderId", request.orderId).
		SetResult(&EmptyResponse{}).
		SetError(&ErrorDetails{}).
		SetBody(request).
		Patch(endpoint)

	if err == nil {
		_, err = processHostingResponse[EmptyResponse](resp)
	}

	return
}

// DeleteHosting deletes an existing hosting order
func (api *hostingApi) DeleteHosting(request DeleteOrderRequest) (response *OrderResponse, err error) {
	endpoint := fmt.Sprintf("%s/orders/{orderId}", api.cfg.AWSHostingApiBaseEndpoint)

	resp, err := api.client.R().
		SetHeader(ApiKeyHeaderName, api.cfg.AWSHostingApiKey).
		SetPathParam("orderId", request.orderId).
		SetResult(&OrderResponse{}).
		SetError(&ErrorDetails{}).
		SetBody(request).
		Delete(endpoint)

	if err == nil {
		response, err = processHostingResponse[OrderResponse](resp)
	}

	return
}

// CreateClient creates a new hosting client
func (api *hostingApi) CreateClient(request CreateClientRequest) (response *ClientResponse, err error) {
	endpoint := fmt.Sprintf("%s/clients", api.cfg.AWSHostingApiBaseEndpoint)

	resp, err := api.client.R().
		SetHeader(ApiKeyHeaderName, api.cfg.AWSHostingApiKey).
		SetResult(&ClientResponse{}).
		SetError(&ErrorDetails{}).
		SetBody(request).
		Post(endpoint)

	if err == nil {
		response, err = processHostingResponse[ClientResponse](resp)
	}

	return
}

// GetClientByEmail get details of the client belonging to a reseller with the provided email
func (api *hostingApi) GetClientByEmail(email, resellerName string) (response *ClientResponse, err error) {

	endpoint := fmt.Sprintf("%s/clients", api.cfg.AWSHostingApiBaseEndpoint)

	resp, err := api.client.R().
		SetHeader(ApiKeyHeaderName, api.cfg.AWSHostingApiKey).
		SetQueryParams(map[string]string{
			"email":        email,
			"resellerName": resellerName,
		}).
		SetResult(&[]ClientResponse{}).
		SetError(&ErrorDetails{}).
		Get(endpoint)

	if resp.StatusCode() == http.StatusNotFound {
		return nil, nil
	}

	if err == nil {
		slice, e := processHostingResponse[[]ClientResponse](resp)
		if slice != nil {
			response, err = &(*slice)[0], e
			return
		}

		response, err = nil, e
		return
	}

	return
}

// CreateClient creates a new hosting client
func (api *hostingApi) CreateReseller(request CreateResellerRequest) (response *ResellerResponse, err error) {
	endpoint := fmt.Sprintf("%s/resellers", api.cfg.AWSHostingApiBaseEndpoint)

	resp, err := api.client.R().
		SetHeader(ApiKeyHeaderName, api.cfg.AWSHostingApiKey).
		SetResult(&ResellerResponse{}).
		SetError(&ErrorDetails{}).
		SetBody(request).
		Post(endpoint)

	if err == nil {
		response, err = processHostingResponse[ResellerResponse](resp)
	}

	return
}

// GetResellerByName get details of the reseller by name
func (api *hostingApi) GetResellerByName(name string) (response *ResellerResponse, err error) {

	endpoint := fmt.Sprintf("%s/resellers", api.cfg.AWSHostingApiBaseEndpoint)

	resp, err := api.client.R().
		SetHeader(ApiKeyHeaderName, api.cfg.AWSHostingApiKey).
		SetQueryParams(map[string]string{
			"resellerName": name,
		}).
		SetResult(&[]ResellerResponse{}).
		SetError(&ErrorDetails{}).
		Get(endpoint)

	if resp.StatusCode() == http.StatusNotFound {
		return nil, nil
	}

	if err == nil {
		slice, e := processHostingResponse[[]ResellerResponse](resp)
		if slice != nil {
			response, err = &(*slice)[0], e
			return
		}

		response, err = nil, e
		return
	}

	return
}
