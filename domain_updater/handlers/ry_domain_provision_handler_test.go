package handlers

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/suite"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message"
	commonmessages "github.com/tucowsinc/tdp-messages-go/message/common"
	rymessages "github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

func TestRyDomainProvisionTestSuite(t *testing.T) {
	suite.Run(t, new(RyDomainProvisionTestSuite))
}

type RyDomainProvisionTestSuite struct {
	suite.Suite
	db     database.Database
	mb     *mocks.MockMessageBus
	s      *mocks.MockMessageBusServer
	tracer *oteltrace.Tracer
}

func (suite *RyDomainProvisionTestSuite) SetupSuite() {
	cfg, err := config.LoadConfiguration("../../.env")
	suite.NoError(err, "Failed to read config from .env")

	cfg.LogLevel = "mute" // suppress log output
	log.Setup(cfg)

	cfg.TracingEnabled = false
	tracer, _, err := tracing.Setup(context.Background(), cfg)
	if err != nil {
		log.Fatal("Error setting up tracing", log.Fields{"error": err})
	}
	suite.tracer = tracer

	db, err := database.New(cfg.PostgresPoolConfig(), cfg.GetDBLogLevel())
	suite.NoError(err, types.LogMessages.DatabaseConnectionFailed)
	suite.db = db
}

func (suite *RyDomainProvisionTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertRyDomainProvisionTestJob(db database.Database) (job *model.Job, err error) {
	tx := db.GetDB()

	domain_name := uuid.New().String()

	data := types.DomainData{
		Name: domain_name,
		Contacts: []types.DomainContact{
			{
				Type:   "admin",
				Handle: "test_handle",
			},
		},
		Pw: "test_pw",
		Nameservers: []types.Nameserver{
			{
				Name:        "test_server",
				IpAddresses: []string{"test_address"},
			},
		},
		Accreditation: types.Accreditation{
			IsProxy:              false,
			TenantId:             "test_tenantId",
			TenantName:           "test_tenantName",
			ProviderId:           "test_providerId",
			ProviderName:         "test_providerName",
			AccreditationId:      "test_accreditationId",
			AccreditationName:    "test_accreditationName",
			ProviderInstanceId:   "test_providerInstanceId",
			ProviderInstanceName: "test_providerInstanceName",
		},
		TenantCustomerId:   "",
		RegistrationPeriod: 10,
		ProviderContactId:  "",
	}

	serializedData, err := json.Marshal(data)
	if err != nil {
		return
	}

	//get a tenant id (doesn't matter which)
	//automatically generated when db is brought up
	var id string
	err = tx.Table("tenant_customer").Select("id").Scan(&id).Error
	if err != nil {
		return
	}

	var jobId string
	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, id, "provision_domain_create", "0268f162-5d83-44d2-894a-ab7578c498fb", serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)

	return
}

func (suite *RyDomainProvisionTestSuite) TestRyDomainProvisionHandler() {
	expectedContext := context.Background()

	job, err := insertRyDomainProvisionTestJob(suite.db)
	suite.NoError(err, "Failed to insert test job")

	envelope := &message.TcWire{CorrelationId: job.ID}

	err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to update test job")

	service := NewWorkerService(suite.mb, suite.db, suite.tracer)

	suite.s.On("Context").Return(expectedContext)
	suite.s.On("Headers").Return(nil)
	suite.s.On("Envelope").Return(envelope)

	msg := &rymessages.DomainCreateResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  true,
			EppCode:    1000,
			EppMessage: "",
		},
	}

	handler := service.RyDomainProvisionHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.s.AssertExpectations(suite.T())
}

func (suite *RyDomainProvisionTestSuite) TestRyDomainProvisionHandlerWithPendingResponse() {
	expectedContext := context.Background()

	job, err := insertRyDomainProvisionTestJob(suite.db)
	suite.NoError(err, "Failed to insert test job")

	envelope := &message.TcWire{CorrelationId: job.ID}

	err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to update test job")

	service := NewWorkerService(suite.mb, suite.db, suite.tracer)

	suite.s.On("Context").Return(expectedContext)
	suite.s.On("Headers").Return(nil)
	suite.s.On("Envelope").Return(envelope)

	msg := &rymessages.DomainCreateResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  true,
			EppCode:    1001,
			EppMessage: "",
			EppCltrid:  "ABC-123",
		},
	}

	handler := service.RyDomainProvisionHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.s.AssertExpectations(suite.T())
}

func (suite *RyDomainProvisionTestSuite) TestRyErrResponseDomainProvisionHandler() {
	expectedContext := context.Background()

	job, err := insertRyDomainProvisionTestJob(suite.db)
	suite.NoError(err, "Failed to insert test job")

	envelope := &message.TcWire{CorrelationId: job.ID}

	err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to update test job")

	service := NewWorkerService(suite.mb, suite.db, suite.tracer)

	suite.s.On("Context").Return(expectedContext)
	suite.s.On("Headers").Return(nil)
	suite.s.On("Envelope").Return(envelope)

	// placeholder for real epp error message
	eppErrMessage := "provision domain failed"
	msg := &rymessages.DomainCreateResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  false,
			EppCode:    types.EppCode.ParameterPolicyError,
			EppMessage: eppErrMessage,
		},
	}

	handler := service.RyDomainProvisionHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	job, err = suite.db.GetJobById(expectedContext, job.ID, false)
	suite.NoError(err, "Failed to fetch updated job")

	suite.Equal("failed", *job.Info.JobStatusName)

	suite.Equal(eppErrMessage, *job.ResultMessage)

	suite.s.AssertExpectations(suite.T())
}
