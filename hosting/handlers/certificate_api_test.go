package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"testing"

	"github.com/go-resty/resty/v2"
	"github.com/google/uuid"
	"github.com/jarcoal/httpmock"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

type CertificateApiTestSuite struct {
	suite.Suite
	api *certificateApi
}

func TestCertificateApiSuite(t *testing.T) {
	suite.Run(t, new(CertificateApiTestSuite))
}

func (suite *CertificateApiTestSuite) SetupSuite() {
	cfg := config.Config{}
	client := resty.New()
	hostingApi := &certificateApi{
		client: client,
		cfg:    cfg,
	}

	cfg.LogLevel = "mute" // suppress log output
	log.Setup(cfg)

	suite.api = hostingApi
}

func (suite *CertificateApiTestSuite) SetupTest() {
	httpmock.Activate()
	httpmock.ActivateNonDefault(suite.api.client.GetClient())
}

func (suite *CertificateApiTestSuite) TearDownTest() {
	httpmock.DeactivateAndReset()
}

func (suite *CertificateApiTestSuite) TestApi_NewCert() {
	domain := "test-domain-name.com"
	requestId := uuid.New().String()
	expectedResponse := CreateCertificateResponse{
		DomainName: domain,
		Message:    "",
		Status:     "queued",
	}
	j, _ := json.Marshal(expectedResponse)

	tests := map[string]struct {
		data         string
		path         string
		responseCode int
		want         *CreateCertificateResponse
		wantErr      error
	}{
		"success": {
			data:         string(j),
			path:         "/newcert",
			responseCode: 200,
			want: &CreateCertificateResponse{
				DomainName: domain,
				Message:    "",
				Status:     "queued",
			},
			wantErr: nil,
		},
	}

	for name, tt := range tests {
		suite.T().Run(name, func(t *testing.T) {
			httpmock.RegisterResponder(http.MethodPost, tt.path, setupMockResponder(tt.responseCode, tt.data))

			got, err := suite.api.CreateCertificate(context.Background(), CreateCertificateRequest{
				Domain:    domain,
				RequestId: requestId,
			},
			)

			if tt.wantErr != nil && errors.Is(err, tt.wantErr) {
				t.Errorf("Create certificate error: %v, wantError: %v", err, tt.wantErr)
				return
			}

			assert.Equal(t, tt.want, got)
		})
	}

}
