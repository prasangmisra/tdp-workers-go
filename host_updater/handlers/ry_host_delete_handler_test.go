package handlers

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-messages-go/message"
	commonmessages "github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	config "github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

type RyHostDeleteTestSuite struct {
	suite.Suite
	db database.Database
	mb *mocks.MockMessageBus
	s  *mocks.MockMessageBusServer
	t  *oteltrace.Tracer
}

func TestRyHostDeleteTestSuite(t *testing.T) {
	suite.Run(t, new(RyHostDeleteTestSuite))
}

func (suite *RyHostDeleteTestSuite) SetupSuite() {
	cfg, err := config.LoadConfiguration("../../.env")
	suite.NoError(err, "Failed to read config from .env")

	cfg.LogLevel = "debug" // suppress log output
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

func (suite *RyHostDeleteTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertRyHostDeleteTestJob(db database.Database, rename bool) (job *model.Job, err error) {
	tx := db.GetDB()

	data := &types.HostDeleteData{
		HostId:   "test_hostId",
		HostName: "ns1.tucows.help",
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
		TenantCustomerId:      "test_tenantCustomerId",
		ProvisionHostDeleteId: types.ToPointer("test_provision_host_delete_id"),
	}

	if rename {
		data.HostDeleteRenameAllowed = true
		data.HostDeleteRenameDomain = "ns2.tucows.help"
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
	err = tx.Raw(sql, id, "provision_host_delete", "0268f162-5d83-44d2-894a-ab7578c498fb", serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	return db.GetJobById(context.Background(), jobId, false)
}

func (suite *RyHostDeleteTestSuite) TestRyHostDeleteHandler() {
	expectedContext := context.Background()

	job, err := insertRyHostDeleteTestJob(suite.db, false)
	suite.NoError(err, "Failed to insert test job")

	err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to delete test job")

	envelope := &message.TcWire{CorrelationId: job.ID}

	suite.s.On("Envelope").Return(envelope)
	suite.s.On("Headers").Return(nil)
	suite.s.On("Context").Return(expectedContext)

	msg := &ryinterface.HostDeleteResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  true,
			EppCode:    1000,
			EppMessage: "",
		},
	}

	service := NewWorkerService(suite.mb, suite.db, suite.t)

	err = service.RyHostDeleteHandler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	job, err = suite.db.GetJobById(expectedContext, job.ID, false)
	suite.NoError(err, "Failed to fetch updated job")

	suite.Equal("completed", *job.Info.JobStatusName)

	suite.s.AssertExpectations(suite.T())
}

func (suite *RyHostDeleteTestSuite) TestRyHostDeleteHandler_Failed() {
	expectedContext := context.Background()

	job, err := insertRyHostDeleteTestJob(suite.db, false)
	suite.NoError(err, "Failed to insert test job")

	err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to delete test job")

	envelope := &message.TcWire{CorrelationId: job.ID}

	suite.s.On("Envelope").Return(envelope)
	suite.s.On("Headers").Return(nil)
	suite.s.On("Context").Return(expectedContext)

	msg := &ryinterface.HostDeleteResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  false,
			EppCode:    2102,
			EppMessage: "",
		},
	}

	service := NewWorkerService(suite.mb, suite.db, suite.t)

	err = service.RyHostDeleteHandler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	job, err = suite.db.GetJobById(expectedContext, job.ID, false)
	suite.NoError(err, "Failed to fetch updated job")

	suite.Equal("failed", *job.Info.JobStatusName)

	suite.s.AssertExpectations(suite.T())
}

func (suite *RyHostDeleteTestSuite) TestRyHostDeleteHandler_Rename() {
	expectedContext := context.Background()

	job, err := insertRyHostDeleteTestJob(suite.db, true)
	suite.NoError(err, "Failed to insert test job")

	err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to delete test job")

	envelope := &message.TcWire{CorrelationId: job.ID}

	suite.mb.On(
		"Send",
		expectedContext,
		mock.Anything,
		mock.AnythingOfType("*ryinterface.HostUpdateRequest"),
		mock.Anything,
	).Return(nil)
	suite.s.On("MessageBus").Return(suite.mb)
	suite.s.On("Envelope").Return(envelope)
	suite.s.On("Headers").Return(nil)
	suite.s.On("Context").Return(expectedContext)

	msg := &ryinterface.HostDeleteResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  false,
			EppCode:    2102,
			EppMessage: "",
		},
	}

	service := NewWorkerService(suite.mb, suite.db, suite.t)

	err = service.RyHostDeleteHandler(suite.s, msg)
	suite.NoError(err, "Failed to handle host delete message")

	renameMsg := &ryinterface.HostUpdateResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  true,
			EppCode:    1000,
			EppMessage: "",
		},
	}

	err = service.RyHostUpdateHandler(suite.s, renameMsg)
	suite.NoError(err, "Failed to handle host update message")

	job, err = suite.db.GetJobById(expectedContext, job.ID, false)
	suite.NoError(err, "Failed to fetch updated job")

	suite.Equal("completed", *job.Info.JobStatusName)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}

func (suite *RyHostDeleteTestSuite) TestRyHostDeleteHandler_Rename_Failed() {
	expectedContext := context.Background()

	job, err := insertRyHostDeleteTestJob(suite.db, true)
	suite.NoError(err, "Failed to insert test job")

	err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to delete test job")

	envelope := &message.TcWire{CorrelationId: job.ID}

	suite.mb.On(
		"Send",
		expectedContext,
		mock.Anything,
		mock.AnythingOfType("*ryinterface.HostUpdateRequest"),
		mock.Anything,
	).Return(nil)
	suite.s.On("MessageBus").Return(suite.mb)
	suite.s.On("Envelope").Return(envelope)
	suite.s.On("Headers").Return(nil)
	suite.s.On("Context").Return(expectedContext)

	msg := &ryinterface.HostDeleteResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  false,
			EppCode:    2102,
			EppMessage: "",
		},
	}

	service := NewWorkerService(suite.mb, suite.db, suite.t)

	err = service.RyHostDeleteHandler(suite.s, msg)
	suite.NoError(err, "Failed to handle host delete message")

	renameMsg := &ryinterface.HostUpdateResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  false,
			EppCode:    2303,
			EppMessage: "",
		},
	}

	err = service.RyHostUpdateHandler(suite.s, renameMsg)
	suite.NoError(err, "Failed to handle host update message")

	job, err = suite.db.GetJobById(expectedContext, job.ID, false)
	suite.NoError(err, "Failed to fetch updated job")

	suite.Equal("failed", *job.Info.JobStatusName)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}

func (suite *RyHostDeleteTestSuite) TestRyHostDeleteHandler_Does_Not_Exist() {
	expectedContext := context.Background()

	job, err := insertRyHostDeleteTestJob(suite.db, false)
	suite.NoError(err, "Failed to insert test job")

	err = suite.db.SetJobStatus(expectedContext, job, "processing", nil)
	suite.NoError(err, "Failed to delete test job")

	envelope := &message.TcWire{CorrelationId: job.ID}

	suite.s.On("Envelope").Return(envelope)
	suite.s.On("Headers").Return(nil)
	suite.s.On("Context").Return(expectedContext)

	msg := &ryinterface.HostDeleteResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  false,
			EppCode:    2303,
			EppMessage: "",
		},
	}

	service := NewWorkerService(suite.mb, suite.db, suite.t)

	err = service.RyHostDeleteHandler(suite.s, msg)
	suite.NoError(err, "Failed to handle message")

	job, err = suite.db.GetJobById(expectedContext, job.ID, false)
	suite.NoError(err, "Failed to fetch updated job")

	suite.Equal("completed", *job.Info.JobStatusName)

	suite.s.AssertExpectations(suite.T())
}
