package handlers

import (
	"context"
	"fmt"

	"github.com/go-resty/resty/v2"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
)

// check that our interface is implemented
var _ CertificateApi = (*certificateApi)(nil)

type CertificateApi interface {
	CreateCertificate(ctx context.Context, request CreateCertificateRequest) (*CreateCertificateResponse, error)
	GetCertificateStatus(ctx context.Context, domainName string) (*GetCertificateStatusResponse, error)
	GetCertificate(ctx context.Context, domainName string) (*GetCertificateResponse, error)
}

type certificateApi struct {
	client *resty.Client
	cfg    config.Config
}

// CreateCertificate sends a request to create a new certificate
// POST /newcert
func (api *certificateApi) CreateCertificate(ctx context.Context, request CreateCertificateRequest) (response *CreateCertificateResponse, err error) {

	endpoint := fmt.Sprintf("%s/newcert", api.cfg.CertBotApiBaseEndpoint)

	resp, err := api.client.R().
		SetContext(ctx).
		SetAuthToken(api.cfg.CertBotApiToken).
		SetResult(&CreateCertificateResponse{}).
		SetError(&CertificateErrorDetails{}).
		SetBody(request).
		Post(endpoint)

	response, err = processCertificateResponse[CreateCertificateResponse](resp)

	return
}

// GetCertificateStatus sends a request to get the status of a certificate
// GET /domain/{name}
func (api *certificateApi) GetCertificateStatus(ctx context.Context, domainName string) (response *GetCertificateStatusResponse, err error) {
	return
}

// GetCertificate sends a request to get a certificate
// GET /getcert/{name}
func (api *certificateApi) GetCertificate(ctx context.Context, domainName string) (response *GetCertificateResponse, err error) {

	endpoint := fmt.Sprintf("%s/getcert/%s", api.cfg.CertBotApiBaseEndpoint, domainName)

	resp, err := api.client.R().
		SetContext(ctx).
		SetAuthToken(api.cfg.CertBotApiToken).
		SetResult(&GetCertificateResponse{}).
		SetError(&CertificateErrorDetails{}).
		Get(endpoint)

	if err == nil {
		response, err = processCertificateResponse[GetCertificateResponse](resp)
	}
	return
}
