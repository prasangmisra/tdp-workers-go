package handlers

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/suite"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	commonmessages "github.com/tucowsinc/tdp-messages-go/message/common"
	rymessages "github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

func TestRyDomainUpdateTestSuite(t *testing.T) {
	suite.Run(t, new(RyDomainUpdateTestSuite))
}

type RyDomainUpdateTestSuite struct {
	suite.Suite
	db database.Database
	mb *mocks.MockMessageBus
	s  *mocks.MockMessageBusServer
	t  *oteltrace.Tracer
}

func (suite *RyDomainUpdateTestSuite) SetupSuite() {
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

func (suite *RyDomainUpdateTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertRyDomainUpdateTestJob(db database.Database) (job *model.Job, err error) {
	tx := db.GetDB()

	pw := "test_pw"
	add_server := &types.Nameserver{
		Name:        "test_server",
		IpAddresses: []string{"test_address"},
	}
	data := types.DomainUpdateData{
		Name: "test_domain_name",
		Contacts: &types.DomainUpdateContactData{
			Add: []types.DomainContact{
				{
					Type:   "admin",
					Handle: "test_handle",
				},
			},
		},
		Pw: &pw,
		Nameservers: struct {
			Add []*types.Nameserver "json:\"add\""
			Rem []*types.Nameserver "json:\"rem\""
		}{
			Add: []*types.Nameserver{
				add_server,
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
		TenantCustomerId: "",
	}

	serializedData, err := json.Marshal(data)
	if err != nil {
		return
	}

	var id string
	err = tx.Table("tenant_customer").Select("id").Scan(&id).Error
	if err != nil {
		return
	}

	var jobId string
	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, id, "provision_domain_update", "0268f162-5d83-44d2-894a-ab7578c498fb", serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)

	return
}

func (suite *RyDomainUpdateTestSuite) TestRyDomainUpdateHandler() {
	expectedContext := context.Background()
	service := NewWorkerService(suite.mb, suite.db, suite.t)

	job, err := insertRyDomainUpdateTestJob(suite.db)
	suite.NoError(err, "Failed to insert test job")

	err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to update test job")

	suite.s.On("Context").Return(expectedContext)
	suite.s.On("Headers").Return(nil)

	msg := &rymessages.DomainUpdateResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  true,
			EppCode:    1000,
			EppMessage: "",
		},
	}

	handler := service.RyDomainUpdateHandler
	err = handler(suite.s, msg, job, suite.db, log.GetLogger())
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.s.AssertExpectations(suite.T())
}

func (suite *RyDomainUpdateTestSuite) TestRyDomainUpdateHandlerWithPendingResponse() {
	expectedContext := context.Background()
	service := NewWorkerService(suite.mb, suite.db, suite.t)

	job, err := insertRyDomainUpdateTestJob(suite.db)
	suite.NoError(err, "Failed to insert test job")

	err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to update test job")

	suite.s.On("Context").Return(expectedContext)
	suite.s.On("Headers").Return(nil)

	msg := &rymessages.DomainUpdateResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  true,
			EppCode:    1001,
			EppMessage: "",
			EppCltrid:  "ABC-123",
		},
	}

	handler := service.RyDomainUpdateHandler
	err = handler(suite.s, msg, job, suite.db, log.GetLogger())
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.s.AssertExpectations(suite.T())
}

func (suite *RyDomainUpdateTestSuite) TestRyErrResponseDomainUpdateHandler() {
	expectedContext := context.Background()
	service := NewWorkerService(suite.mb, suite.db, suite.t)

	job, err := insertRyDomainUpdateTestJob(suite.db)
	suite.NoError(err, "Failed to insert test job")

	err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to update test job")

	suite.s.On("Context").Return(expectedContext)
	suite.s.On("Headers").Return(nil)

	eppErrMessage := "failed to update domain"
	msg := &rymessages.DomainUpdateResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  false,
			EppCode:    types.EppCode.ObjectDoesNotExist,
			EppMessage: eppErrMessage,
		},
	}
	handler := service.RyDomainUpdateHandler
	err = handler(suite.s, msg, job, suite.db, log.GetLogger())
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	job, err = suite.db.GetJobById(expectedContext, job.ID, false)
	suite.NoError(err, "Failed to fetch updated job")

	suite.Equal("failed", *job.Info.JobStatusName)

	suite.Equal(eppErrMessage, *job.ResultMessage)

	suite.s.AssertExpectations(suite.T())
}
