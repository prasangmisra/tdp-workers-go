package handlers

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/anypb"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	commonmessages "github.com/tucowsinc/tdp-messages-go/message/common"
	jobmessage "github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

func TestDomainRedeemTestSuite(t *testing.T) {
	suite.Run(t, new(DomainRedeemTestSuite))
}

type DomainRedeemTestSuite struct {
	suite.Suite
	db     database.Database
	mb     *mocks.MockMessageBus
	s      *mocks.MockMessageBusServer
	tracer *oteltrace.Tracer
}

func (suite *DomainRedeemTestSuite) SetupSuite() {
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

func (suite *DomainRedeemTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertDomainRedeemTestJob(db database.Database, withPrice bool) (job *model.Job, data *types.DomainRedeemData, err error) {
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
		ProvisionDomainRedeemId: uuid.New().String(),
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

	if withPrice {
		data.Price = &types.OrderPrice{Amount: 1045, Currency: "USD", Fraction: 100}
	}

	serializedData, err := json.Marshal(data)
	if err != nil {
		return
	}

	var jobId string
	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, id, "provision_domain_redeem", data.ProvisionDomainRedeemId, serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)

	return
}

func (suite *DomainRedeemTestSuite) TestDomainRedeemHandler() {
	job, data, err := insertDomainRedeemTestJob(suite.db, false)
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

	rgpExtension := new(extension.RgpUpdateRequest)
	rgpExtension.RgpOp = "request"
	anyExtension, err := anypb.New(rgpExtension)
	suite.NoError(err, "Failed to marshal to proto any type")

	expectedMsg := ryinterface.DomainUpdateRequest{
		Name:       data.Name,
		Extensions: map[string]*anypb.Any{"rgp": anyExtension},
	}

	expectedHeaders := map[string]any{
		"reply_to":       "WorkerJobDomainProvisionUpdate",
		"correlation_id": job.ID,
	}

	service := NewWorkerService(suite.mb, suite.db, suite.tracer)

	suite.mb.On("Send", expectedContext, expectedDestination, &expectedMsg, expectedHeaders).Return(nil)
	suite.s.On("MessageBus").Return(suite.mb)
	suite.s.On("Headers").Return(expectedHeaders)
	suite.s.On("Context").Return(expectedContext)

	handler := service.DomainRedeemHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}

func (suite *DomainRedeemTestSuite) TestDomainRedeemHandlerWithPrice() {
	job, data, err := insertDomainRedeemTestJob(suite.db, true)
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

	rgpExtension, err := anypb.New(&extension.RgpUpdateRequest{RgpOp: "request"})
	suite.NoError(err, "Failed to marshal to proto any type for RGP extension")

	feeExtension, err := anypb.New(&extension.FeeTransformRequest{Fee: []*extension.FeeFee{{Price: &commonmessages.Money{CurrencyCode: "USD", Units: 10, Nanos: 450000000}}}})
	suite.NoError(err, "Failed to marshal to proto any type for Fee extension")

	expectedMsg := ryinterface.DomainUpdateRequest{
		Name:       data.Name,
		Extensions: map[string]*anypb.Any{"rgp": rgpExtension, "fee": feeExtension},
	}

	expectedHeaders := map[string]any{
		"reply_to":       "WorkerJobDomainProvisionUpdate",
		"correlation_id": job.ID,
	}

	service := NewWorkerService(suite.mb, suite.db, suite.tracer)

	suite.mb.On("Send", expectedContext, expectedDestination, &expectedMsg, expectedHeaders).Return(nil)
	suite.s.On("MessageBus").Return(suite.mb)
	suite.s.On("Headers").Return(expectedHeaders)
	suite.s.On("Context").Return(expectedContext)

	handler := service.DomainRedeemHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}
