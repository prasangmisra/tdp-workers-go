package handlers

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	jobmessage "github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

func TestDomainRedeemReportTestSuite(t *testing.T) {
	suite.Run(t, new(DomainRedeemReportTestSuite))
}

type DomainRedeemReportTestSuite struct {
	suite.Suite
	db     database.Database
	mb     *mocks.MockMessageBus
	s      *mocks.MockMessageBusServer
	tracer *oteltrace.Tracer
}

func (suite *DomainRedeemReportTestSuite) SetupSuite() {
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

func (suite *DomainRedeemReportTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertDomainRedeemReportTestJob(db database.Database) (job *model.Job, data *types.DomainRedeemData, err error) {
	tx := db.GetDB()

	//get a tenant id (doesn't matter which)
	//automatically generated when db is brought up
	var id string
	err = tx.Table("tenant_customer").Select("id").Scan(&id).Error
	if err != nil {
		return
	}

	data = &types.DomainRedeemData{
		Name:                    "test_name",
		TenantCustomerId:        id,
		ProvisionDomainRedeemId: "",
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
	}

	serializedData, err := json.Marshal(data)
	if err != nil {
		return
	}

	var parentJobId string
	sql := `SELECT job_create(?, ?, ?, ?)`
	err = tx.Raw(sql, id, "provision_domain_redeem_report", "0268f162-5d83-44d2-894a-ab7578c498fb", serializedData).Scan(&parentJobId).Error
	if err != nil {
		return
	}

	var jobId string
	sql = `SELECT job_submit(?, ?, ?, ?, ?)`
	err = tx.Raw(sql, id, "provision_domain_redeem", nil, serializedData, parentJobId).Scan(&jobId).Error
	if err != nil {
		return
	}

	sql = `UPDATE job SET status_id = tc_id_from_name('job_status','completed') WHERE id = ?`
	err = tx.Raw(sql, parentJobId).Scan(&jobId).Error
	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)

	return
}

func (suite *DomainRedeemReportTestSuite) TestDomainRedeemReportHandler() {
	job, data, err := insertDomainRedeemReportTestJob(suite.db)
	suite.NoError(err, "Failed to insert test job")

	msg := &jobmessage.Notification{
		JobId:          job.ID,
		Type:           "domain_redeem",
		Status:         "status",
		ReferenceId:    "0268f162-5d83-44d2-894a-ab7578c498fb",
		ReferenceTable: "1234",
	}

	expectedContext := context.Background()
	expectedDestination := types.GetTransformQueue(accreditationName)
	workerLogger := log.CreateChildLogger()
	expectedMsg, err := toDomainRedeemReport(*data, workerLogger)
	suite.NoError(err, "Failed to parse DomainRedeemData into DomainUpdateRequest")

	expectedHeaders := map[string]any{
		"reply_to":       "WorkerJobDomainProvisionUpdate",
		"correlation_id": job.ID,
	}

	service := NewWorkerService(suite.mb, suite.db, suite.tracer)

	suite.mb.On("Send", expectedContext, expectedDestination, expectedMsg, expectedHeaders).Return(nil)
	suite.s.On("MessageBus").Return(suite.mb)
	suite.s.On("Headers").Return(expectedHeaders)
	suite.s.On("Context").Return(expectedContext)

	handler := service.DomainRedeemReportHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}
