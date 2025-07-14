package handlers

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/suite"

	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message"
	commonmessages "github.com/tucowsinc/tdp-messages-go/message/common"
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
	accreditationName = "test-accreditationName"
)

func TestRyHostProvisionTestSuite(t *testing.T) {
	suite.Run(t, new(RyHostProvisionTestSuite))
}

type RyHostProvisionTestSuite struct {
	suite.Suite
	db database.Database
	mb *mocks.MockMessageBus
	s  *mocks.MockMessageBusServer
	t  *oteltrace.Tracer
}

func (suite *RyHostProvisionTestSuite) SetupSuite() {
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

func (suite *RyHostProvisionTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertRyHostProvisionTestJob(db database.Database) (job *model.Job, err error) {
	tx := db.GetDB()

	data := types.HostData{
		HostId:    "",
		HostName:  "test_host_name",
		HostAddrs: nil,
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
		ProvisionHostId:  "",
		TenantCustomerId: "",
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
	err = tx.Raw(sql, id, "provision_host_create", "0268f162-5d83-44d2-894a-ab7578c498fb", serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	return db.GetJobById(context.Background(), jobId, false)
}

func (suite *RyHostProvisionTestSuite) TestRyHostProvisionHandler() {
	expectedContext := context.Background()

	job, err := insertRyHostProvisionTestJob(suite.db)
	suite.NoError(err, "Failed to insert test job")

	err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to update test job")

	envelope := &message.TcWire{CorrelationId: job.ID}

	service := NewWorkerService(suite.mb, suite.db, suite.t)

	suite.s.On("Context").Return(expectedContext)
	suite.s.On("Headers").Return(nil)
	suite.s.On("Envelope").Return(envelope)

	msg := &ryinterface.HostCreateResponse{
		Name:        "",
		CreatedDate: timestamppb.Now(),
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  true,
			EppCode:    1000,
			EppMessage: "",
		},
	}

	handler := service.RyHostProvisionHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.s.AssertExpectations(suite.T())
}
