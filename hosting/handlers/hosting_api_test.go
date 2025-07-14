package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"testing"

	"github.com/go-resty/resty/v2"
	"github.com/jarcoal/httpmock"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

type HostingApiTestSuite struct {
	suite.Suite
	api *hostingApi
}

func TestHostingApiSuite(t *testing.T) {
	suite.Run(t, new(HostingApiTestSuite))
}

func (suite *HostingApiTestSuite) SetupSuite() {
	cfg := config.Config{AWSHostingApiKey: "test-api-key"}
	client := resty.New()
	hostingApi := &hostingApi{
		client: client,
		cfg:    cfg,
	}

	suite.api = hostingApi

	cfg.LogLevel = "mute" // suppress log output
	log.Setup(cfg)
}

func (suite *HostingApiTestSuite) SetupTest() {
	httpmock.Activate()
	httpmock.ActivateNonDefault(suite.api.client.GetClient())
}

func (suite *HostingApiTestSuite) TearDownTest() {
	httpmock.DeactivateAndReset()
}

func (suite *HostingApiTestSuite) TestApi_CreateHosting() {
	orderId := "test-order-id"
	expectedResponse := OrderResponse{Id: orderId}
	j, _ := json.Marshal(expectedResponse)

	tests := map[string]struct {
		data         string
		path         string
		responseCode int
		want         *OrderResponse
		wantErr      error
	}{
		"success": {
			data:         string(j),
			path:         "/orders",
			responseCode: 200,
			want:         &OrderResponse{Id: orderId},
			wantErr:      nil,
		},
	}

	for name, tt := range tests {
		suite.T().Run(name, func(t *testing.T) {

			httpmock.RegisterResponder(http.MethodPost, tt.path, setupMockResponder(tt.responseCode, tt.data))

			got, err := suite.api.CreateHosting(CreateOrderRequest{
				Domain: DomainDetails{
					Name: "test-domain-name.com",
				},
				ClientId:    "test-client-id",
				ProductId:   "test-product-id",
				AwsRegionId: "test-region",
			})

			if tt.wantErr != nil && !errors.Is(err, tt.wantErr) {
				t.Errorf("CreateHosting error: %v, wantError: %v", err, tt.wantErr)
				return
			}

			assert.Equal(t, tt.want, got)
			assert.Equal(t, tt.want.Id, got.Id)
		})
	}
}

func (suite *HostingApiTestSuite) TestApi_CreateHosting_ErrorResponse() {
	domainName := "test.com"
	expectedResponse := &ErrorDetails{Message: fmt.Sprintf("domain name %s already registered", domainName)}
	j, _ := json.Marshal(expectedResponse)

	tests := map[string]struct {
		data         string
		path         string
		responseCode int
		want         *OrderResponse
		wantErr      bool
	}{
		"success": {
			data:         string(j),
			path:         "/orders",
			responseCode: 400,
			want:         nil,
			wantErr:      true,
		},
	}

	for name, tt := range tests {
		suite.T().Run(name, func(t *testing.T) {

			httpmock.RegisterResponder(http.MethodPost, tt.path, setupMockResponder(tt.responseCode, tt.data))

			got, err := suite.api.CreateHosting(CreateOrderRequest{
				Domain: DomainDetails{
					Name: "test-domain-name.com",
				},
				ClientId:    "test-client-id",
				ProductId:   "test-product-id",
				AwsRegionId: "test-region",
			})

			if (err != nil) != tt.wantErr {
				t.Errorf("CreateHosting error: %v, wantError: %v", err, tt.wantErr)
				return
			}

			assert.Equal(t, tt.want, got)
			assert.Equal(t, err.Error(), fmt.Sprintf("%s: %s", errorMessages[http.MethodPost], expectedResponse.Message))
		})
	}
}

func (suite *HostingApiTestSuite) TestApi_CreateHosting_Error() {
	expectedError := errors.New("error calling hosting backend")

	tests := map[string]struct {
		data         string
		path         string
		responseCode int
		want         *OrderResponse
		wantErr      error
	}{
		"success": {
			data:         "{}",
			path:         "/orders",
			responseCode: 500,
			want:         nil,
			wantErr:      expectedError,
		},
	}

	for name, tt := range tests {
		suite.T().Run(name, func(t *testing.T) {

			httpmock.RegisterResponder(http.MethodPost, tt.path, setupMockErrorResponder(tt.wantErr))

			got, err := suite.api.CreateHosting(CreateOrderRequest{
				Domain: DomainDetails{
					Name: "test-domain-name.com",
				},
				ClientId:    "test-client-id",
				ProductId:   "test-product-id",
				AwsRegionId: "test-region",
			})

			if tt.wantErr != nil && !errors.Is(err, tt.wantErr) {
				t.Errorf("CreateHosting error: %v, wantError: %v", err, tt.wantErr)
				return
			}

			assert.ErrorContains(t, err, tt.wantErr.Error())
			assert.Equal(t, tt.want, got)
		})
	}
}

func (suite *HostingApiTestSuite) TestApi_UpdateHosting() {
	orderId := "test-order-id"
	expectedResponse := OrderResponse{Id: orderId}
	j, _ := json.Marshal(expectedResponse)

	tests := map[string]struct {
		data         string
		path         string
		responseCode int
		want         *OrderResponse
		wantErr      error
	}{
		"success": {
			data:         string(j),
			path:         fmt.Sprintf("/orders/%v", orderId),
			responseCode: 200,
			want:         &OrderResponse{Id: orderId},
			wantErr:      nil,
		},
	}

	for name, tt := range tests {
		suite.T().Run(name, func(t *testing.T) {

			httpmock.RegisterResponder(http.MethodPatch, tt.path, setupMockResponder(tt.responseCode, tt.data))

			got, err := suite.api.UpdateHosting(UpdateOrderRequest{orderId: orderId, IsActive: true})
			if tt.wantErr != nil && !errors.Is(err, tt.wantErr) {
				t.Errorf("UpdateHosting error: %v, wantError: %v", err, tt.wantErr)
				return
			}

			assert.Equal(t, tt.want, got)
			assert.Equal(t, tt.want.Id, got.Id)
		})
	}
}

func (suite *HostingApiTestSuite) TestApi_UpdateHosting_ErrorResponse() {
	orderId := "test-order-id"
	expectedResponse := &ErrorDetails{Message: fmt.Sprintf("order id %s does not exist", orderId)}
	j, _ := json.Marshal(expectedResponse)

	tests := map[string]struct {
		data         string
		path         string
		responseCode int
		want         *OrderResponse
		wantErr      bool
	}{
		"success": {
			data:         string(j),
			path:         fmt.Sprintf("/orders/%v", orderId),
			responseCode: 404,
			want:         nil,
			wantErr:      true,
		},
	}

	for name, tt := range tests {
		suite.T().Run(name, func(t *testing.T) {

			httpmock.RegisterResponder(http.MethodPatch, tt.path, setupMockResponder(tt.responseCode, tt.data))

			got, err := suite.api.UpdateHosting(UpdateOrderRequest{orderId: orderId, IsActive: true})

			if (err != nil) != tt.wantErr {
				t.Errorf("UpdateHosting error: %v, wantError: %v", err, tt.wantErr)
				return
			}

			assert.Equal(t, tt.want, got)
			assert.Equal(t, err.Error(), fmt.Sprintf("%s: %s", errorMessages[http.MethodPatch], expectedResponse.Message))
		})
	}
}

func (suite *HostingApiTestSuite) TestApi_UpdateHosting_Error() {
	orderId := "test-order-id"
	expectedError := errors.New("error calling hosting backend")

	tests := map[string]struct {
		data         string
		path         string
		responseCode int
		want         *OrderResponse
		wantErr      error
	}{
		"success": {
			data:         "{}",
			path:         fmt.Sprintf("/orders/%v", orderId),
			responseCode: 500,
			want:         nil,
			wantErr:      expectedError,
		},
	}

	for name, tt := range tests {
		suite.T().Run(name, func(t *testing.T) {

			httpmock.RegisterResponder(http.MethodPatch, tt.path, setupMockErrorResponder(tt.wantErr))

			got, err := suite.api.UpdateHosting(UpdateOrderRequest{orderId: orderId, IsActive: true})

			if tt.wantErr != nil && !errors.Is(err, tt.wantErr) {
				t.Errorf("UpdateHosting error: %v, wantError: %v", err, tt.wantErr)
				return
			}

			assert.ErrorContains(t, err, tt.wantErr.Error())
			assert.Equal(t, tt.want, got)
		})
	}
}

func (suite *HostingApiTestSuite) TestApi_CreateClient() {
	clientId := "test-client-id"
	expectedResponse := ClientResponse{Id: clientId}
	j, _ := json.Marshal(expectedResponse)

	tests := map[string]struct {
		data         string
		path         string
		responseCode int
		want         *ClientResponse
		wantErr      error
	}{
		"success": {
			data:         string(j),
			path:         "/clients",
			responseCode: 200,
			want:         &ClientResponse{Id: clientId},
			wantErr:      nil,
		},
	}

	for name, tt := range tests {
		suite.T().Run(name, func(t *testing.T) {

			httpmock.RegisterResponder(http.MethodPost, tt.path, setupMockResponder(tt.responseCode, tt.data))

			got, err := suite.api.CreateClient(CreateClientRequest{
				ClientDetails: ClientDetails{
					Name:         "test-name",
					Email:        "test@email.com",
					ResellerName: "test-reseller-name",
				},
				Password: "test-password",
			})
			if tt.wantErr != nil && !errors.Is(err, tt.wantErr) {
				t.Errorf("CreateClient error: %v, wantError: %v", err, tt.wantErr)
				return
			}

			assert.Equal(t, tt.want, got)
			assert.Equal(t, tt.want.Id, got.Id)
		})
	}
}

func (suite *HostingApiTestSuite) TestApi_CreateClient_ErrorResponse() {
	clientEmail := "test@email.com"
	expectedResponse := &ErrorDetails{Message: fmt.Sprintf("client email %s already registered", clientEmail)}
	j, _ := json.Marshal(expectedResponse)

	tests := map[string]struct {
		data         string
		path         string
		responseCode int
		want         *ClientResponse
		wantErr      bool
	}{
		"success": {
			data:         string(j),
			path:         "/clients",
			responseCode: 400,
			want:         nil,
			wantErr:      true,
		},
	}

	for name, tt := range tests {
		suite.T().Run(name, func(t *testing.T) {

			httpmock.RegisterResponder(http.MethodPost, tt.path, setupMockResponder(tt.responseCode, tt.data))

			got, err := suite.api.CreateClient(CreateClientRequest{
				ClientDetails: ClientDetails{
					Name:         "test-name",
					Email:        "test@email.com",
					ResellerName: "test-reseller-name",
				},
				Password: "test-password",
			})

			if (err != nil) != tt.wantErr {
				t.Errorf("CreateClient error: %v, wantError: %v", err, tt.wantErr)
				return
			}

			assert.Equal(t, tt.want, got)
			assert.Equal(t, err.Error(), fmt.Sprintf("%s: %s", errorMessages[http.MethodPost], expectedResponse.Message))
		})
	}
}

func (suite *HostingApiTestSuite) TestApi_CreateClient_Error() {
	expectedError := errors.New("error calling hosting backend")

	tests := map[string]struct {
		data         string
		path         string
		responseCode int
		want         *ClientResponse
		wantErr      error
	}{
		"success": {
			data:         "{}",
			path:         "/clients",
			responseCode: 500,
			want:         nil,
			wantErr:      expectedError,
		},
	}

	for name, tt := range tests {
		suite.T().Run(name, func(t *testing.T) {

			httpmock.RegisterResponder(http.MethodPost, tt.path, setupMockErrorResponder(tt.wantErr))

			got, err := suite.api.CreateClient(CreateClientRequest{
				ClientDetails: ClientDetails{
					Name:         "test-name",
					Email:        "test@email.com",
					ResellerName: "test-reseller-name",
				},
				Password: "test-password",
			})

			if tt.wantErr != nil && !errors.Is(err, tt.wantErr) {
				t.Errorf("CreateClient error: %v, wantError: %v", err, tt.wantErr)
				return
			}

			assert.ErrorContains(t, err, tt.wantErr.Error())
			assert.Equal(t, tt.want, got)
		})
	}
}

func (suite *HostingApiTestSuite) TestApi_GetClientByEmail() {
	expectedResponse := ClientResponse{
		Id:       "test-client-id",
		IsActive: true,
		ClientDetails: ClientDetails{
			Name:  "test-name",
			Email: "test@email.com",
		},
	}
	slice := []ClientResponse{expectedResponse}
	j, _ := json.Marshal(slice)

	tests := map[string]struct {
		data         string
		path         string
		responseCode int
		want         *ClientResponse
		wantErr      error
	}{
		"success": {
			data:         string(j),
			path:         "/clients",
			responseCode: 200,
			want:         &slice[0],
			wantErr:      nil,
		},
	}

	for name, tt := range tests {
		suite.T().Run(name, func(t *testing.T) {

			httpmock.RegisterResponder(http.MethodGet, tt.path, setupMockResponder(tt.responseCode, tt.data))

			got, err := suite.api.GetClientByEmail(expectedResponse.Email, mock.Anything)
			if tt.wantErr != nil && !errors.Is(err, tt.wantErr) {
				t.Errorf("GetClientByEmail error: %v, wantError: %v", err, tt.wantErr)
				return
			}

			assert.Equal(t, tt.want, got)
			assert.Equal(t, tt.want.Id, got.Id)
		})
	}
}

func (suite *HostingApiTestSuite) TestApi_GetClientByEmail_ErrorResponse() {
	expectedResponse := &ErrorDetails{Message: "clients not found"}
	j, _ := json.Marshal(expectedResponse)

	tests := map[string]struct {
		data         string
		path         string
		responseCode int
		want         *ClientResponse
		wantErr      bool
	}{
		"success": {
			data:         string(j),
			path:         "/clients",
			responseCode: 404,
			want:         nil,
			wantErr:      false,
		},
	}

	for name, tt := range tests {
		suite.T().Run(name, func(t *testing.T) {

			httpmock.RegisterResponder(http.MethodGet, tt.path, setupMockResponder(tt.responseCode, tt.data))

			got, err := suite.api.GetClientByEmail(mock.Anything, mock.Anything)

			if (err != nil) != tt.wantErr {
				t.Errorf("GetClientByEmail error: %v, wantError: %v", err, tt.wantErr)
				return
			}

			assert.Equal(t, tt.want, got)
		})
	}
}

func (suite *HostingApiTestSuite) TestApi_GetClientByEmail_Error() {
	expectedError := errors.New("error calling hosting backend")

	tests := map[string]struct {
		data         string
		path         string
		responseCode int
		want         *ClientResponse
		wantErr      error
	}{
		"success": {
			data:         "{}",
			path:         "/clients",
			responseCode: 500,
			want:         nil,
			wantErr:      expectedError,
		},
	}

	for name, tt := range tests {
		suite.T().Run(name, func(t *testing.T) {

			httpmock.RegisterResponder(http.MethodGet, tt.path, setupMockErrorResponder(tt.wantErr))

			got, err := suite.api.GetClientByEmail(mock.Anything, mock.Anything)

			if tt.wantErr != nil && !errors.Is(err, tt.wantErr) {
				t.Errorf("GetClientByEmail error: %v, wantError: %v", err, tt.wantErr)
				return
			}

			assert.ErrorContains(t, err, tt.wantErr.Error())
			assert.Equal(t, tt.want, got)
		})
	}
}

func (suite *HostingApiTestSuite) TestApi_UpdateHostingCertificate() {
	orderId := "test-order-id"
	expectedResponse := OrderResponse{Id: orderId}
	j, _ := json.Marshal(expectedResponse)

	tests := map[string]struct {
		data         string
		path         string
		responseCode int
		want         *EmptyResponse
		wantErr      error
	}{
		"success": {
			data:         string(j),
			path:         fmt.Sprintf("/orders/certificate/%v", orderId),
			responseCode: 200,
			want:         &EmptyResponse{},
			wantErr:      nil,
		},
	}

	for name, tt := range tests {
		suite.T().Run(name, func(t *testing.T) {

			httpmock.RegisterResponder(http.MethodPatch, tt.path, setupMockResponder(tt.responseCode, tt.data))

			err := suite.api.UpdateHostingCertificate(UpdateCertificateRequest{orderId: orderId, CertificateDetails: CertificateDetails{}})
			if tt.wantErr != nil && !errors.Is(err, tt.wantErr) {
				t.Errorf("UpdateHostingCertificate error: %v, wantError: %v", err, tt.wantErr)
				return
			}

			assert.Equal(t, tt.wantErr, err)
		})
	}
}

func (suite *HostingApiTestSuite) TestApi_UpdateHostingCertificate_ErrorResponse() {
	orderId := "test-order-id"
	expectedResponse := &ErrorDetails{Message: "unable to parse certificate body"}
	j, _ := json.Marshal(expectedResponse)

	tests := map[string]struct {
		data         string
		path         string
		responseCode int
		want         *EmptyResponse
		wantErr      bool
	}{
		"success": {
			data:         string(j),
			path:         fmt.Sprintf("/orders/certificate/%v", orderId),
			responseCode: 400,
			want:         nil,
			wantErr:      true,
		},
	}

	for name, tt := range tests {
		suite.T().Run(name, func(t *testing.T) {

			httpmock.RegisterResponder(http.MethodPatch, tt.path, setupMockResponder(tt.responseCode, tt.data))

			err := suite.api.UpdateHostingCertificate(UpdateCertificateRequest{orderId: orderId, CertificateDetails: CertificateDetails{}})

			if (err != nil) != tt.wantErr {
				t.Errorf("UpdateHostingCertificate error: %v, wantError: %v", err, tt.wantErr)
				return
			}

			assert.Equal(t, err.Error(), fmt.Sprintf("%s: %s", errorMessages[http.MethodPatch], expectedResponse.Message))
		})
	}
}

func (suite *HostingApiTestSuite) TestApi_UpdateHostingCertificate_Error() {
	orderId := "test-order-id"
	expectedError := errors.New("error calling hosting backend")

	tests := map[string]struct {
		data         string
		path         string
		responseCode int
		want         *EmptyResponse
		wantErr      error
	}{
		"success": {
			data:         "{}",
			path:         fmt.Sprintf("/orders/certificate/%v", orderId),
			responseCode: 500,
			want:         nil,
			wantErr:      expectedError,
		},
	}

	for name, tt := range tests {
		suite.T().Run(name, func(t *testing.T) {

			httpmock.RegisterResponder(http.MethodPatch, tt.path, setupMockErrorResponder(tt.wantErr))

			err := suite.api.UpdateHostingCertificate(UpdateCertificateRequest{orderId: orderId, CertificateDetails: CertificateDetails{}})

			if tt.wantErr != nil && !errors.Is(err, tt.wantErr) {
				t.Errorf("UpdateHostingCertificate error: %v, wantError: %v", err, tt.wantErr)
				return
			}

			assert.ErrorContains(t, err, tt.wantErr.Error())
		})
	}
}
