package rest_client

import (
	"encoding/json"
	"testing"

	"github.com/jarcoal/httpmock"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/suite"
	config "github.com/tucowsinc/tdp-workers-go/pkg/config"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

type ClientTestSuite struct {
	suite.Suite
}

func TestClientTestSuite(t *testing.T) {
	suite.Run(t, new(ClientTestSuite))
}

func (suite *ClientTestSuite) SetupSuite() {
	config, err := config.LoadConfiguration("../../.env")
	assert.NoError(suite.T(), err, "Failed to read config from .env")

	config.LogLevel = "mute" // suppress log output
	log.Setup(config)
}

func (suite *ClientTestSuite) TestRestClient_Execute_Success() {

	expectedResponse := &MockGetResponse{Id: "test-id", DomainName: "test.com"}
	jsonResponse, _ := json.Marshal(expectedResponse)

	tests := map[string]struct {
		data     string
		path     string
		respCode int
		want     *ApiResponse[MockGetResponse, MockErrorResponse]
		wantErr  error
	}{
		"success": {
			data:     string(jsonResponse),
			path:     "https://api.com",
			respCode: 200,
			want: &ApiResponse[MockGetResponse, MockErrorResponse]{
				StatusCode: 200,
				IsSuccess:  true,
				Body: &MockGetResponse{
					Id:         expectedResponse.Id,
					DomainName: expectedResponse.DomainName,
				},
			},
			wantErr: nil,
		},
	}

	for name, tt := range tests {
		suite.T().Run(name, func(t *testing.T) {
			defer httpmock.DeactivateAndReset()

			client := CreateClient[MockGetResponse, MockErrorResponse](false)
			request := client.NewApiRequest(tt.path, GET).
				SetHeaders(map[string]string{"x-api-key": "test-api-key"}).
				SetQueryParams(map[string]string{"reseller-name": "test-reseller-name"})

			httpmock.Activate()
			httpmock.ActivateNonDefault(client.client.GetClient())
			httpmock.RegisterResponder("GET", tt.path, newResponder(tt.respCode, tt.data, "application/json"))

			got, err := client.Execute(request)

			if tt.wantErr != nil && !errors.Is(err, tt.wantErr) {
				t.Errorf("Execute() error = %v, wantError = %v", err, tt.wantErr)
				return
			}

			assert.Equal(t, tt.want, got)
		})
	}
}

func (suite *ClientTestSuite) TestRestClient_Execute_ApiError() {
	expectedResponse := &MockErrorResponse{Message: "domain already exists"}
	jsonResponse, _ := json.Marshal(expectedResponse)

	tests := map[string]struct {
		data     string
		path     string
		respCode int
		want     *ApiResponse[MockGetResponse, MockErrorResponse]
		wantErr  error
	}{
		"success_error_response": {
			data:     string(jsonResponse),
			path:     "https://api.com",
			respCode: 400,
			want: &ApiResponse[MockGetResponse, MockErrorResponse]{
				StatusCode: 400,
				Error: &MockErrorResponse{
					Message: expectedResponse.Message,
				},
			},
			wantErr: nil,
		},
	}

	for name, tt := range tests {
		suite.T().Run(name, func(t *testing.T) {
			defer httpmock.DeactivateAndReset()

			client := CreateClient[MockGetResponse, MockErrorResponse](false)
			request := client.NewApiRequest(tt.path, POST).
				SetHeaders(map[string]string{"x-api-key": "test-api-key"}).
				SetPayload(MockRequest{DomainName: "test-domain-name"})

			httpmock.Activate()
			httpmock.ActivateNonDefault(client.client.GetClient())
			httpmock.RegisterResponder("POST", tt.path, newResponder(tt.respCode, tt.data, "application/json"))

			got, err := client.Execute(request)

			if tt.wantErr != nil && !errors.Is(err, tt.wantErr) {
				t.Errorf("Execute() error = %v, wantError = %v", err, tt.wantErr)
				return
			}

			assert.Equal(t, tt.want, got)
		})
	}
}

func newResponder(s int, c string, ct string) httpmock.Responder {
	resp := httpmock.NewStringResponse(s, c)
	resp.Header.Set("Content-Type", ct)

	return httpmock.ResponderFromResponse(resp)
}

type MockGetResponse struct {
	Id         string `json:"id"`
	DomainName string `json:"domain_name"`
}

type MockErrorResponse struct {
	Message string `json:"message"`
}

type MockRequest struct {
	DomainName string `json:"domain_name"`
}
