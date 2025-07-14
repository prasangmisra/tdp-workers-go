package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"testing"

	"github.com/google/uuid"
	"github.com/jarcoal/httpmock"
	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	jobmessage "github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-shared-go/dns"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

var testCert = "-----BEGIN CERTIFICATE-----\nMIIDjDCCAnSgAwIBAgIIC8fghz87xvwwDQYJKoZIhvcNAQELBQAwKDEmMCQGA1UE\nAxMdUGViYmxlIEludGVybWVkaWF0ZSBDQSA3YWI3NGEwHhcNMjQwNzI5MTUwMjQ1\nWhcNMjQwODAxMTUwMjQ0WjAiMSAwHgYDVQQDExdjbmFtZS1vay50ZHAudHVjb3dz\nLm5ldDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKj8ReCW4O3/8O77\nXytC4R/LE1hT4gLo4dy/HkIkpLi5nO6MdTwzktm2jZU3mMyZ3JV+Lope+qhe+WxL\nyQNpWx0sgstlT7cuDhy6EWGDpgV9bC2skJLM2rJZld6HHafT1eOalulXwYgTSkZA\nsOMJBL3VdWWVq5M3Ll9lS1hzn7kv12YhMxRqMd9SXSknICseJpj22Ik2t/KAuxZ0\nWFPHFsus9lYOTIFPzibqWiHuWBLU/rYVIr5uk9Cd/UKmVTyw3iPAoLGVrLb3UxYJ\n99/k5S6303C5nDVCnNGdZkTe1lLndvNwTtcyI3E+SXuwgqDNM4ZbfKVmMdPFf13E\nLWxCXuUCAwEAAaOBvzCBvDAOBgNVHQ8BAf8EBAMCBaAwHQYDVR0lBBYwFAYIKwYB\nBQUHAwEGCCsGAQUFBwMCMAwGA1UdEwEB/wQCMAAwHQYDVR0OBBYEFMnFHhoG5tY3\ncm4v8QExiRj86VhxMB8GA1UdIwQYMBaAFGpJM/iDgNjn9iWNK6bcR1vhutG+MD0G\nA1UdEQQ2MDSCF2NuYW1lLW9rLnRkcC50dWNvd3MubmV0ghkqLmNuYW1lLW9rLnRk\ncC50dWNvd3MubmV0MA0GCSqGSIb3DQEBCwUAA4IBAQCR53QLzZwN72A3LCVJwUEh\n5QuiXWfKjSmykBua/9lu4fqWBYl9qxF6BSx1rpjs+mJWIwniaYq63MxB4Jrel05B\noryQtonjL9G3j3Yc8XrdLUvARxzjCE97bEfNtm4gD3TMI7/tJQ0gLUvyMi8O1/Fs\naMQhm3kBKCSKvPqQ/bpBiib4iHWkGzxNAIG8rSNGSs8oxv+hQIREtuhPkGmpHT0y\nsaeFs8PZ6ZqAoJaRo1hzH8jwDt1dxxvUTA78dauLe+mUCatul9Gx1fLjLe5Ccu7M\n+G7jesOSbTEhv6TwG5R5ogGy64Q7jxsSJfhRkKZTcfb/B0F487+xG/fi4iFCgfDa\n-----END CERTIFICATE-----\n"

type CertificateProvisionTestSuite struct {
	suite.Suite
	ctx     context.Context
	db      database.Database
	cfg     config.Config
	service *WorkerService
	mb      *mocks.MockMessageBus
	s       *mocks.MockMessageBusServer
}

func TestCertificateProvisionSuite(t *testing.T) {
	suite.Run(t, new(CertificateProvisionTestSuite))
}

func (suite *CertificateProvisionTestSuite) SetupSuite() {
	// TODO: might need to change this; this worker might have custom config
	cfg, err := config.LoadConfiguration("../../.env")
	suite.NoError(err, "Failed to read config from .env")

	cfg.LogLevel = "mute" // suppress log output
	log.Setup(cfg)

	db, err := database.New(cfg.PostgresPoolConfig(), cfg.GetDBLogLevel())
	suite.NoError(err, types.LogMessages.DatabaseConnectionFailed)
	suite.db = db
	suite.cfg = cfg
	suite.ctx = context.Background()
}

func (suite *CertificateProvisionTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}

	resolver, _ := dns.New()
	suite.service = NewWorkerService(suite.mb, suite.db, resolver, suite.cfg)

	httpmock.Activate()
	httpmock.ActivateNonDefault(suite.service.certificateApi.client.GetClient())
}

func getTestDomainName() string {
	return fmt.Sprintf("%s.sexy", uuid.New().String())
}

func insertCertificateProvisionTestJob(db database.Database, domain string) (job *model.Job, provisionId string, err error) {
	tx := db.GetDB().Begin()

	// create provision hosting certificate create record first

	insertOrderSQL := `
    INSERT INTO "order"
        (tenant_customer_id, type_id)
        VALUES ((SELECT id FROM tenant_customer where true limit 1), (SELECT id FROM v_order_type WHERE product_name='hosting' AND name='create'))
        RETURNING id;`

	insertOIHCSQL := `
    INSERT INTO order_item_create_hosting_client(
            tenant_customer_id,
            email
        ) VALUES(
            (SELECT id FROM v_tenant_customer LIMIT 1),
            ? 
        ) RETURNING id`

	insertOICHSQL := `
    INSERT INTO order_item_create_hosting(
        order_id,
        tenant_customer_id,
        client_id,
        domain_name,
        product_id,
        region_id
    ) VALUES(
        ?,
        (SELECT id FROM v_tenant_customer LIMIT 1),
        ?,
        ?,
        tc_id_from_name('hosting_product','Wordpress'),
        tc_id_from_name('hosting_region', 'US East (N. Virginia)')
    ) RETURNING id`

	insertProvisionSQL := `
	INSERT INTO provision_hosting_certificate_create (
            domain_name,
            hosting_id,
            tenant_customer_id
        ) VALUES (
		 			?,
					?,
					(SELECT id FROM v_tenant_customer LIMIT 1)
                ) RETURNING id`

	// startOrderSQL := `
	// UPDATE "order" SET status_id = order_next_status($1,TRUE) WHERE id=$2;`

	var id string
	if err = tx.Table("tenant_customer").Select("id").Scan(&id).Error; err != nil {
		return
	}

	var orderId string
	err = tx.Raw(insertOrderSQL).Scan(&orderId).Error

	if err != nil {
		return
	}

	testEmail := fmt.Sprintf("test-email-%s@domain.com", uuid.New().String())

	var oihcId string
	err = tx.Raw(insertOIHCSQL, testEmail).Scan(&oihcId).Error

	if err != nil {
		return
	}

	var oichId string
	err = tx.Raw(insertOICHSQL, orderId, oihcId, domain).Scan(&oichId).Error

	if err != nil {
		return
	}

	// create provision record

	err = tx.Raw(insertProvisionSQL, domain, oichId).Scan(&provisionId).Error

	if err != nil {
		return
	}

	serializedData, err := json.Marshal(struct {
		DomainName string `json:"domain_name"`
		RequestId  string `json:"request_id"`
	}{
		DomainName: domain,
		RequestId:  oichId,
	})
	if err != nil {
		job = nil
		return
	}

	tx.Commit()

	tx = db.GetDB().Begin()
	var jobId string
	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, id, "provision_hosting_certificate_create", provisionId, serializedData).
		Scan(&jobId).Error

	if err != nil {
		return
	}
	tx.Commit()

	job, err = db.GetJobById(context.Background(), jobId, false)
	return
}

func (suite *CertificateProvisionTestSuite) TestCertificateProvisionHandler() {

	domain := getTestDomainName()
	job, provisionId, err := insertCertificateProvisionTestJob(suite.db, domain)

	suite.NoError(err, "Failed to insert test job")

	msg := &jobmessage.Notification{
		JobId:          job.ID,
		Type:           "provision_hosting_certificate_create",
		Status:         "status",
		ReferenceId:    provisionId,
		ReferenceTable: "provision_hosting_certificate_create",
	}

	expectedResponse := CreateCertificateResponse{
		DomainName: domain,
		Message:    "",
		Status:     "queued",
	}
	j, _ := json.Marshal(expectedResponse)

	httpmock.RegisterResponder(http.MethodPost, "/newcert", setupMockResponder(200, string(j)))

	suite.s.On("Context").Return(suite.ctx)

	err = suite.service.HostingCertificateProvisionHandler(suite.s, msg)
	suite.NoError(err)

	job, err = suite.db.GetJobById(suite.ctx, job.ID, false)

	suite.NoError(err)
	suite.Equal(job.StatusID, suite.db.GetJobStatusId("completed_conditionally"))

	suite.mb.AssertExpectations(suite.T())
}

func (suite *CertificateProvisionTestSuite) TestCertificateProvisionHandler_CertificateExists() {

	domain := getTestDomainName()
	job, provisionId, err := insertCertificateProvisionTestJob(suite.db, domain)

	suite.NoError(err, "Failed to insert test job")

	msg := &jobmessage.Notification{
		JobId:          job.ID,
		Type:           "provision_hosting_certificate_create",
		Status:         "status",
		ReferenceId:    provisionId,
		ReferenceTable: "provision_hosting_certificate_create",
	}

	expectedResponse := CertificateErrorDetails{
		Error: "domain already processed",
	}
	j, _ := json.Marshal(expectedResponse)

	secondRes := GetCertificateResponse{
		Cert:      testCert,
		Chain:     "test-chain",
		Domain:    "test-domain",
		Fullchain: "test-fullchain",
		Privkey:   "test-private-key",
	}
	res, _ := json.Marshal(secondRes)

	httpmock.RegisterResponder(http.MethodPost, "/newcert", setupMockResponder(400, string(j)))

	uri := fmt.Sprintf("/getcert/%s", domain)
	httpmock.RegisterResponder(http.MethodGet, uri, setupMockResponder(200, string(res)))

	suite.s.On("Context").Return(suite.ctx)

	err = suite.service.HostingCertificateProvisionHandler(suite.s, msg)
	suite.NoError(err)

	job, err = suite.db.GetJobById(suite.ctx, job.ID, false)

	suite.NoError(err)
	suite.Equal(job.StatusID, suite.db.GetJobStatusId("completed"))

	suite.mb.AssertExpectations(suite.T())
}

// modify this specific test. we need to run its own setup, and set the url and timeout
// to values that will cause us to get the error we are looking for
func (suite *CertificateProvisionTestSuite) TestCertificateProvisionHandler_CertbotTimeout() {
	domain := getTestDomainName()

	cfg := suite.cfg
	cfg.CertBotApiTimeout = 2
	cfg.CertBotApiBaseEndpoint = "http://google.com:81"

	suite.service = NewWorkerService(suite.mb, suite.db, nil, cfg)

	httpmock.Deactivate()

	job, provisionId, err := insertCertificateProvisionTestJob(suite.db, domain)
	suite.NoError(err, "Failed to insert test job")

	msg := &jobmessage.Notification{
		JobId:          job.ID,
		Type:           "provision_hosting_certificate_create",
		Status:         "status",
		ReferenceId:    provisionId,
		ReferenceTable: "provision_hosting_certificate_create",
	}

	suite.s.On("Context").Return(suite.ctx)

	err = suite.service.HostingCertificateProvisionHandler(suite.s, msg)
	suite.Error(err)

	job, err = suite.db.GetJobById(suite.ctx, job.ID, false)

	suite.NoError(err)
	suite.Equal("submitted", suite.db.GetJobStatusName(job.StatusID))

	suite.mb.AssertExpectations(suite.T())
}
