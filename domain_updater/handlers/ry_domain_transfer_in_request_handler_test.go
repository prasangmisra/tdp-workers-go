package handlers

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message"
	commonmessages "github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestRyDomainTransferInRequestTestSuite(t *testing.T) {
	suite.Run(t, new(RyDomainTransferInRequestTestSuite))
}

type RyDomainTransferInRequestTestSuite struct {
	suite.Suite
	db     database.Database
	mb     *mocks.MockMessageBus
	s      *mocks.MockMessageBusServer
	tracer *oteltrace.Tracer
}

func (suite *RyDomainTransferInRequestTestSuite) SetupSuite() {
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

func (suite *RyDomainTransferInRequestTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertRyDomainTransferInRequestTestJob(db database.Database) (job *model.Job, pdtr *model.ProvisionDomainTransferInRequest, err error) {
	tx := db.GetDB()

	var tenantCustomerId string
	err = tx.Table("tenant_customer").Select("id").Scan(&tenantCustomerId).Error
	if err != nil {
		return
	}

	type accreditation struct {
		Id   string `json:"id"`
		Name string `json:"name"`
	}

	acc := accreditation{}

	err = tx.Table("accreditation").Select("id", "name").Scan(&acc).Error
	if err != nil {
		return
	}

	var accTldId string
	err = tx.Table("accreditation_tld").Select("id").Scan(&accTldId).Error
	if err != nil {
		return
	}

	pdtr = &model.ProvisionDomainTransferInRequest{
		DomainName:         "test-domain.sexy",
		AccreditationID:    acc.Id,
		AccreditationTldID: accTldId,
		TenantCustomerID:   tenantCustomerId,
		StatusID:           db.GetProvisionStatusId("processing"),
	}

	err = tx.Create(pdtr).Error
	if err != nil {
		return
	}

	data := &types.DomainTransferInRequestData{
		Name:             "test-domain.sexy",
		Pw:               "test_pw",
		TransferPeriod:   1,
		TenantCustomerId: tenantCustomerId,
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
		ProvisionDomainTransferInRequestId: pdtr.ID,
	}

	serializedData, err := json.Marshal(data)
	if err != nil {
		return
	}

	var jobId string
	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, tenantCustomerId, "provision_domain_transfer_in_request", pdtr.ID, serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)

	return
}

func (suite *RyDomainTransferInRequestTestSuite) TestRyDomainTransferInRequestHandler() {
	expectedContext := context.Background()

	job, _, err := insertRyDomainTransferInRequestTestJob(suite.db)
	suite.NoError(err, "Failed to insert test job")

	err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to update test job")

	envelope := &message.TcWire{CorrelationId: job.ID}

	msg := &ryinterface.DomainTransferResponse{
		Name:          "example-transferin-domain.sexy",
		RequestedBy:   "test_requested_by",
		RequestedDate: timestamppb.Now(),
		ActionBy:      "test_action_by",
		ActionDate:    timestamppb.Now(),
		ExpiryDate:    timestamppb.Now(),
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  true,
			EppCode:    1001,
			EppMessage: "",
		},
	}

	service := NewWorkerService(suite.mb, suite.db, suite.tracer)

	suite.s.On("Context").Return(expectedContext)
	suite.s.On("Headers").Return(nil)
	suite.s.On("Envelope").Return(envelope)

	handler := service.RyDomainTransferRouter
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)
}
