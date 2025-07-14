package handlers

import (
	"context"
	"encoding/json"
	"net"
	"strings"
	"testing"

	"github.com/stretchr/testify/suite"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	jobmessage "github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

const (
	accreditationName = "test-accreditation"
)

func TestHostProvisionTestSuite(t *testing.T) {
	suite.Run(t, new(HostProvisionTestSuite))
}

type HostProvisionTestSuite struct {
	suite.Suite
	db database.Database
	mb *mocks.MockMessageBus
	s  *mocks.MockMessageBusServer
	t  *oteltrace.Tracer
}

func (suite *HostProvisionTestSuite) SetupSuite() {
	cfg, err := config.LoadConfiguration("../../.env")
	suite.NoError(err, "Failed to read config from .env")

	cfg.LogLevel = "mute" // suppress log output
	log.Setup(cfg)

	cfg.TracingEnabled = false
	tracer, _, err := tracing.Setup(context.Background(), cfg)
	if err != nil {
		log.Fatal("Error setting up tracing", log.Fields{"error": err})
	}
	suite.t = tracer

	db, err := database.New(cfg.PostgresPoolConfig(), cfg.GetDBLogLevel())
	suite.NoError(err, types.LogMessages.DatabaseConnectionFailed)
	suite.db = db
}

func (suite *HostProvisionTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func getTestHostData(same_accreds bool) (data *types.HostData, err error) {
	data = &types.HostData{
		HostId: "",
		HostAddrs: []string{
			"192.168.0.1",
		},
		Accreditation: types.Accreditation{
			IsProxy:              false,
			TenantId:             "test_tenantId",
			TenantName:           "test_tenantName",
			ProviderId:           "test_providerId",
			ProviderName:         "test_providerName",
			AccreditationId:      "test_accreditationId",
			AccreditationName:    accreditationName,
			ProviderInstanceId:   "test_providerInstanceId",
			ProviderInstanceName: "test_providerInstanceName",
		},
		ProvisionHostId:  "",
		TenantCustomerId: "",
	}

	if same_accreds {
		data.HostAccreditationTld = types.AccreditationTld{
			TldId:           "test_tldId",
			AccreditationId: "test_accreditationId",
			TenantName:      "opensrs",
		}
	} else {
		data.HostIpRequiredNonAuth = true
		data.HostAccreditationTld = types.AccreditationTld{
			TldId:           "test_tldId",
			AccreditationId: "test_accreditationId_1",
			TenantName:      "opensrs",
		}
	}

	return
}

func insertHostProvisionTestJob(db database.Database, hostname string, same_accreds bool, ipv6_support bool) (job *model.Job, data *types.HostData, err error) {
	tx := db.GetDB()

	tld := hostname[strings.LastIndex(hostname, ".")+1:]

	data, err = getTestHostData(same_accreds)
	if err != nil {
		return
	}

	data.HostName = hostname

	var AccreditationTldId string
	sql := `SELECT accreditation_tld_id FROM v_accreditation_tld WHERE tld_name = ? AND tenant_name = 'opensrs'`
	err = tx.Raw(sql, tld).Scan(&AccreditationTldId).Error
	if err != nil {
		return
	}
	data.HostAccreditationTld.AccreditationTldId = AccreditationTldId

	if ipv6_support {
		sql = `Update v_attribute SET value = 'true' WHERE key = 'tld.dns.ipv6_support' AND accreditation_tld_id = ?`
		err = tx.Exec(sql, AccreditationTldId).Error
		if err != nil {
			return
		}
	}

	serializedData, err := json.Marshal(data)
	if err != nil {
		return
	}

	//get a tenant id (doesn't matter which)
	//automatically generated when db is brought up
	var tenant_customer_id string
	err = tx.Table("tenant_customer").Select("id").Scan(&tenant_customer_id).Error
	if err != nil {
		return
	}

	var jobId string
	sql = `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, tenant_customer_id, "provision_host_create", "0268f162-5d83-44d2-894a-ab7578c498fb", serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)

	return
}

func (suite *HostProvisionTestSuite) TestHostProvisionHandler() {
	job, data, err := insertHostProvisionTestJob(suite.db, "ns1.tucows.help", true, false)
	suite.NoError(err, "Failed to insert test job")

	expectedContext := context.Background()

	expectedDestination := types.GetTransformQueue(accreditationName)
	expectedMsg := ryinterface.HostCreateRequest{
		Name:      data.HostName,
		Addresses: []string{"192.168.0.1"},
	}
	expectedHeaders := map[string]any{
		"reply_to":       "WorkerJobHostProvisionUpdate",
		"correlation_id": job.ID,
	}

	service := NewWorkerService(suite.mb, suite.db, suite.t)

	suite.mb.On("Send", expectedContext, expectedDestination, &expectedMsg, expectedHeaders).Return(nil)
	suite.s.On("MessageBus").Return(suite.mb)
	suite.s.On("Headers").Return(expectedHeaders)
	suite.s.On("Context").Return(expectedContext)

	msg := &jobmessage.Notification{
		JobId:          job.ID,
		Type:           "",
		Status:         "",
		ReferenceId:    "",
		ReferenceTable: "",
	}

	err = service.HostProvisionHandler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}

func (suite *HostProvisionTestSuite) TestHostProvisionHandler_WithDigAddresses() {
	expectedContext := context.Background()

	lookupIP = func(host string) ([]net.IP, error) {
		return []net.IP{net.ParseIP("199.59.243.228")}, nil
	}
	defer func() {
		lookupIP = net.LookupIP // reset to default after test
	}()
	job, data, err := insertHostProvisionTestJob(suite.db, "ns1.tucows.xyz", false, false)
	suite.NoError(err, "Failed to insert test job")

	suite.db.GetAccreditationByName(expectedContext, accreditationName)

	expectedAddresses := []string{"199.59.243.228"}

	expectedDestination := types.GetTransformQueue(accreditationName)
	expectedMsg := ryinterface.HostCreateRequest{
		Name:      data.HostName,
		Addresses: expectedAddresses,
	}
	expectedHeaders := map[string]any{
		"reply_to":       "WorkerJobHostProvisionUpdate",
		"correlation_id": job.ID,
	}

	service := NewWorkerService(suite.mb, suite.db, suite.t)

	suite.mb.On("Send", expectedContext, expectedDestination, &expectedMsg, expectedHeaders).Return(nil)
	suite.s.On("MessageBus").Return(suite.mb)
	suite.s.On("Headers").Return(expectedHeaders)
	suite.s.On("Context").Return(expectedContext)

	msg := &jobmessage.Notification{
		JobId:          job.ID,
		Type:           "",
		Status:         "",
		ReferenceId:    "",
		ReferenceTable: "",
	}

	err = service.HostProvisionHandler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}

func (suite *HostProvisionTestSuite) TestHostProvisionHandler_WithDigAddresses_Ipv6Supported() {
	job, data, err := insertHostProvisionTestJob(suite.db, "a.nic.xyz", false, true)
	suite.NoError(err, "Failed to insert test job")

	expectedContext := context.Background()
	expectedAddresses := []string{"194.169.218.42", "2001:67c:13cc::1:42"}

	expectedDestination := types.GetTransformQueue(accreditationName)
	expectedMsg := ryinterface.HostCreateRequest{
		Name:      data.HostName,
		Addresses: expectedAddresses,
	}
	expectedHeaders := map[string]any{
		"reply_to":       "WorkerJobHostProvisionUpdate",
		"correlation_id": job.ID,
	}

	service := NewWorkerService(suite.mb, suite.db, suite.t)

	suite.mb.On("Send", expectedContext, expectedDestination, &expectedMsg, expectedHeaders).Return(nil)
	suite.s.On("MessageBus").Return(suite.mb)
	suite.s.On("Headers").Return(expectedHeaders)
	suite.s.On("Context").Return(expectedContext)

	msg := &jobmessage.Notification{
		JobId:          job.ID,
		Type:           "",
		Status:         "",
		ReferenceId:    "",
		ReferenceTable: "",
	}

	err = service.HostProvisionHandler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}

func (suite *HostProvisionTestSuite) TestHostProvisionHandler_WithDigAddresses_Ipv6NotSupported() {
	job, data, err := insertHostProvisionTestJob(suite.db, "a.nic.help", false, false)
	suite.NoError(err, "Failed to insert test job")

	expectedContext := context.Background()
	expectedAddresses := []string{"194.169.218.158"} // IPv6 addresses skipped

	expectedDestination := types.GetTransformQueue(accreditationName)
	expectedMsg := ryinterface.HostCreateRequest{
		Name:      data.HostName,
		Addresses: expectedAddresses,
	}
	expectedHeaders := map[string]any{
		"reply_to":       "WorkerJobHostProvisionUpdate",
		"correlation_id": job.ID,
	}

	service := NewWorkerService(suite.mb, suite.db, suite.t)

	suite.mb.On("Send", expectedContext, expectedDestination, &expectedMsg, expectedHeaders).Return(nil)
	suite.s.On("MessageBus").Return(suite.mb)
	suite.s.On("Headers").Return(expectedHeaders)
	suite.s.On("Context").Return(expectedContext)

	msg := &jobmessage.Notification{
		JobId:          job.ID,
		Type:           "",
		Status:         "",
		ReferenceId:    "",
		ReferenceTable: "",
	}

	err = service.HostProvisionHandler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}
