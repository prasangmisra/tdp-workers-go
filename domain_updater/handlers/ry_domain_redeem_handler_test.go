package handlers

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	commonmessages "github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	rymessages "github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

const (
	accreditationName = "test-accreditationName"
)

func TestRyDomainRedeemTestSuite(t *testing.T) {
	suite.Run(t, new(RyDomainRedeemTestSuite))
}

type RyDomainRedeemTestSuite struct {
	suite.Suite
	db     database.Database
	mb     *mocks.MockMessageBus
	s      *mocks.MockMessageBusServer
	tracer *oteltrace.Tracer
}

func (suite *RyDomainRedeemTestSuite) SetupSuite() {
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

func (suite *RyDomainRedeemTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertRyDomainRedeemTestJob(db database.Database, id string) (job *model.Job, data *types.DomainRedeemData, err error) {
	tx := db.GetDB()

	var domainId string
	sql := `SELECT id FROM domain LIMIT 1`
	err = tx.Raw(sql).Scan(&domainId).Error
	if err != nil {
		return
	}

	var customerId string
	err = tx.Table("tenant_customer").Select("id").Scan(&customerId).Error
	if err != nil {
		return
	}

	var accId string
	sql = `SELECT tc_id_from_name('accreditation',?)`
	err = tx.Raw(sql, "opensrs-uniregistry").Scan(&accId).Error
	if err != nil {
		return
	}

	sql = `INSERT INTO provision_domain_redeem(
				domain_name,
				domain_id,
				tenant_customer_id,
				accreditation_id,
				id
			) VALUES(
				?,
				?,
				?,
				?,
				?
			)`
	err = tx.Raw(sql, "test-name.sexy", domainId, customerId, accId, id).Scan(&domainId).Error
	if err != nil {
		return
	}

	data = &types.DomainRedeemData{
		Name:                    "test-domain.sexy",
		TenantCustomerId:        "",
		ProvisionDomainRedeemId: "",
		Accreditation: types.Accreditation{
			IsProxy:              false,
			TenantId:             "test-tenantId",
			TenantName:           "test-tenantName",
			ProviderId:           "test-providerId",
			ProviderName:         "test-providerName",
			AccreditationId:      "test-accreditationId",
			AccreditationName:    "test-accreditationName",
			ProviderInstanceId:   "test-providerInstanceId",
			ProviderInstanceName: "test-providerInstanceName",
		},
	}

	serializedData, err := json.Marshal(data)
	if err != nil {
		return
	}

	var jobId string
	sql = `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, customerId, "provision_domain_redeem", id, serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)

	return
}

func (suite *RyDomainRedeemTestSuite) TestRyDomainRedeemHandler() {
	expectedContext := context.Background()

	id := uuid.New().String()
	job, data, err := insertRyDomainRedeemTestJob(suite.db, id)
	suite.NoError(err, "Failed to insert test job")

	err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to update test job")

	msg := &ryinterface.DomainUpdateResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  true,
			EppCode:    1000,
			EppMessage: "",
		},
		Extensions: map[string]*anypb.Any{},
	}

	expectedDestination := types.GetTransformQueue(accreditationName)

	rgpExtension := new(extension.RgpUpdateRequest)
	rgpExtension.RgpOp = "report"
	domainData := "name:[test-domain.sexy]\nstatus s=\"[]\"\ncrDate:[0001-01-01 00:00:00 +0000 UTC]\nexDate:[0001-01-01 00:00:00 +0000 UTC]\n"
	rgpExtension.RgpReport = &extension.RgpUpdateRequest_RgpReport{
		PreData:   domainData,
		PostData:  domainData,
		DelTime:   timestamppb.New(data.DeleteDate),
		ResTime:   timestamppb.New(data.RestoreDate),
		ResReason: types.RedeemRestoreReason,
		Statement1: &extension.RgpUpdateRequest_RgpStatement{
			Statement: types.RedeemStatement1,
		},
		Statement2: &extension.RgpUpdateRequest_RgpStatement{
			Statement: types.RedeemStatement2,
		},
	}
	anyExtension, err := anypb.New(rgpExtension)
	suite.NoError(err, "Failed to parse rgp message")

	expectedMsg := ryinterface.DomainUpdateRequest{
		Name: data.Name,
		Extensions: map[string]*anypb.Any{
			"rgp": anyExtension,
		},
	}
	expectedHeaders := map[string]any{
		"reply_to":       "WorkerJobDomainProvisionUpdate",
		"correlation_id": job.ID,
	}

	// domain info to sync expiry after redemption
	domainInfoRequest := &rymessages.DomainInfoRequest{
		Name: "test-domain.sexy",
	}

	domainInfoResponse := &rymessages.DomainInfoResponse{
		Name:       "test-domain.sexy",
		ExpiryDate: timestamppb.New(time.Now().AddDate(1, 0, 0)),
	}

	suite.mb.On("Send", expectedContext, expectedDestination, &expectedMsg, expectedHeaders).Return(nil)
	suite.s.On("MessageBus").Return(suite.mb)
	suite.s.On("Headers").Return(expectedHeaders)
	suite.s.On("Context").Return(expectedContext)

	suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), types.GetTransformQueue("test-accreditationName"), domainInfoRequest, mock.Anything).Return(
		messagebus.RpcResponse{
			Server:  suite.s,
			Message: domainInfoResponse,
			Err:     nil,
		},
		nil,
	)

	service := NewWorkerService(suite.mb, suite.db, suite.tracer)
	handler := service.RyDomainRedeemHandler
	err = handler(suite.s, msg, job, suite.db, log.GetLogger())

	suite.NoError(err, types.LogMessages.HandleMessageFailed)
	suite.NoError(err, "Failed to handle redeem request")
}

func (suite *RyDomainRedeemTestSuite) TestRyDomainRedeemHandlerWithPendingResponse() {
	expectedContext := context.Background()

	id := uuid.New().String()
	job, data, err := insertRyDomainRedeemTestJob(suite.db, id)
	suite.NoError(err, "Failed to insert test job")

	err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to update test job")

	msg := &ryinterface.DomainUpdateResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  true,
			EppCode:    1001,
			EppMessage: "",
			EppCltrid:  "ABC-123",
		},
	}

	expectedDestination := types.GetTransformQueue(accreditationName)

	rgpExtension := new(extension.RgpUpdateRequest)
	rgpExtension.RgpOp = "report"
	domainData := "name:[test-domain.sexy]\nstatus s=\"[]\"\ncrDate:[0001-01-01 00:00:00 +0000 UTC]\nexDate:[0001-01-01 00:00:00 +0000 UTC]\n"
	rgpExtension.RgpReport = &extension.RgpUpdateRequest_RgpReport{
		PreData:   domainData,
		PostData:  domainData,
		DelTime:   timestamppb.New(data.DeleteDate),
		ResTime:   timestamppb.New(data.RestoreDate),
		ResReason: types.RedeemRestoreReason,
		Statement1: &extension.RgpUpdateRequest_RgpStatement{
			Statement: types.RedeemStatement1,
		},
		Statement2: &extension.RgpUpdateRequest_RgpStatement{
			Statement: types.RedeemStatement2,
		},
	}
	anyExtension, err := anypb.New(rgpExtension)
	suite.NoError(err, "Failed to parse rgp message")

	expectedMsg := ryinterface.DomainUpdateRequest{
		Name: data.Name,
		Extensions: map[string]*anypb.Any{
			"rgp": anyExtension,
		},
	}
	expectedHeaders := map[string]any{
		"reply_to":       "WorkerJobDomainProvisionUpdate",
		"correlation_id": job.ID,
	}

	// domain info to sync expiry after redemption
	domainInfoRequest := &rymessages.DomainInfoRequest{
		Name: "test-domain.sexy",
	}

	domainInfoResponse := &rymessages.DomainInfoResponse{
		Name:       "test-domain.sexy",
		ExpiryDate: timestamppb.New(time.Now().AddDate(1, 0, 0)),
	}

	suite.mb.On("Send", expectedContext, expectedDestination, &expectedMsg, expectedHeaders).Return(nil)
	suite.s.On("MessageBus").Return(suite.mb)
	suite.s.On("Headers").Return(expectedHeaders)
	suite.s.On("Context").Return(expectedContext)

	suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), types.GetTransformQueue("test-accreditationName"), domainInfoRequest, mock.Anything).Return(
		messagebus.RpcResponse{
			Server:  suite.s,
			Message: domainInfoResponse,
			Err:     nil,
		},
		nil,
	)

	service := NewWorkerService(suite.mb, suite.db, suite.tracer)
	handler := service.RyDomainRedeemHandler
	err = handler(suite.s, msg, job, suite.db, log.GetLogger())

	suite.NoError(err, types.LogMessages.HandleMessageFailed)
	suite.NoError(err, "Failed to handle redeem request")
}

func (suite *RyDomainRedeemTestSuite) TestRyErrResponseDomainRedeemHandler() {
	expectedContext := context.Background()

	id := uuid.New().String()
	job, data, err := insertRyDomainRedeemTestJob(suite.db, id)
	suite.NoError(err, "Failed to insert test job")

	err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to update test job")

	eppErrMessage := "failed to redeem domain; object does not exist"
	msg := &ryinterface.DomainUpdateResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  false,
			EppCode:    types.EppCode.ObjectDoesNotExist,
			EppMessage: eppErrMessage,
		},
		Extensions: map[string]*anypb.Any{},
	}

	expectedDestination := types.GetTransformQueue(accreditationName)

	rgpExtension := new(extension.RgpUpdateRequest)
	rgpExtension.RgpOp = "report"
	domainData := "name:[test-domain.sexy]\nstatus s=\"[]\"\ncrDate:[0001-01-01 00:00:00 +0000 UTC]\nexDate:[0001-01-01 00:00:00 +0000 UTC]\n"
	rgpExtension.RgpReport = &extension.RgpUpdateRequest_RgpReport{
		PreData:   domainData,
		PostData:  domainData,
		DelTime:   timestamppb.New(data.DeleteDate),
		ResTime:   timestamppb.New(data.RestoreDate),
		ResReason: types.RedeemRestoreReason,
		Statement1: &extension.RgpUpdateRequest_RgpStatement{
			Statement: types.RedeemStatement1,
		},
		Statement2: &extension.RgpUpdateRequest_RgpStatement{
			Statement: types.RedeemStatement2,
		},
	}
	anyExtension, err := anypb.New(rgpExtension)
	suite.NoError(err, "Failed to parse rgp message")

	expectedMsg := ryinterface.DomainUpdateRequest{
		Name: data.Name,
		Extensions: map[string]*anypb.Any{
			"rgp": anyExtension,
		},
	}
	expectedHeaders := map[string]any{
		"reply_to":       "WorkerJobDomainProvisionUpdate",
		"correlation_id": job.ID,
	}

	suite.mb.On("Send", expectedContext, expectedDestination, &expectedMsg, expectedHeaders).Return(nil)
	suite.s.On("MessageBus").Return(suite.mb)
	suite.s.On("Headers").Return(expectedHeaders)
	suite.s.On("Context").Return(expectedContext)

	service := NewWorkerService(suite.mb, suite.db, suite.tracer)

	handler := service.RyDomainRedeemHandler
	err = handler(suite.s, msg, job, suite.db, log.GetLogger())
	suite.NoError(err, types.LogMessages.HandleMessageFailed)
	suite.NoError(err, "Failed to handle redeem request")

	job, err = suite.db.GetJobById(expectedContext, job.ID, false)
	suite.NoError(err, "Failed to fetch updated job")

	suite.Equal("failed", *job.Info.JobStatusName)

	suite.Equal(eppErrMessage, *job.ResultMessage)

	suite.NoError(err, types.LogMessages.HandleMessageFailed)
	suite.NoError(err, "Failed to handle redeem request")
}
