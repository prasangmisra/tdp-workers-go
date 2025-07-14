package handlers

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/anypb"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	commonmessages "github.com/tucowsinc/tdp-messages-go/message/common"
	jobmessage "github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"

	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

func TestDomainTransferInRequestTestSuite(t *testing.T) {
	suite.Run(t, new(DomainTransferInRequestTestSuite))
}

type DomainTransferInRequestTestSuite struct {
	suite.Suite
	db     database.Database
	mb     *mocks.MockMessageBus
	s      *mocks.MockMessageBusServer
	tracer *oteltrace.Tracer
}

func (suite *DomainTransferInRequestTestSuite) SetupSuite() {
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

func (suite *DomainTransferInRequestTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertDomainTransferInRequestTestJob(db database.Database, withPrice bool) (job *model.Job, data *types.DomainTransferInRequestData, err error) {
	tx := db.GetDB()

	var tenantCustomerId string
	err = tx.Table("tenant_customer").Select("id").Scan(&tenantCustomerId).Error
	if err != nil {
		return
	}

	data = &types.DomainTransferInRequestData{
		Name:             "example-transferin-domain.sexy",
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
	err = tx.Raw(sql, tenantCustomerId, "provision_domain_transfer_in_request", "0268f162-5d83-44d2-894a-ab7578c498fb", serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)

	return
}

func (suite *DomainTransferInRequestTestSuite) TestDomainTransferInRequestHandler() {
	job, data, err := insertDomainTransferInRequestTestJob(suite.db, false)
	suite.NoError(err, "Failed to insert test job")

	periodUnit := commonmessages.PeriodUnit_YEAR

	msg := &jobmessage.Notification{
		JobId:          job.ID,
		Type:           "domain.transfer",
		Status:         "status",
		ReferenceId:    "0268f162-5d83-44d2-894a-ab7578c498fb",
		ReferenceTable: "1234",
	}

	expectedContext := context.Background()
	expectedDestination := types.GetTransformQueue(accreditationName)
	expectedMsg := ryinterface.DomainTransferRequest{
		Name:           data.Name,
		Pw:             data.Pw,
		Period:         &data.TransferPeriod,
		PeriodUnit:     &periodUnit,
		RegistrantRoid: nil,
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

	handler := service.DomainTransferInRequestHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}

func (suite *DomainTransferInRequestTestSuite) TestDomainTransferInRequestHandlerWithPrice() {
	job, data, err := insertDomainTransferInRequestTestJob(suite.db, true)
	suite.NoError(err, "Failed to insert test job")

	periodUnit := commonmessages.PeriodUnit_YEAR

	msg := &jobmessage.Notification{
		JobId:          job.ID,
		Type:           "domain.transfer",
		Status:         "status",
		ReferenceId:    "0268f162-5d83-44d2-894a-ab7578c498fb",
		ReferenceTable: "1234",
	}

	expectedContext := context.Background()
	expectedDestination := types.GetTransformQueue(accreditationName)
	expectedExtension, _ := anypb.New(&extension.FeeTransformRequest{Fee: []*extension.FeeFee{{Price: &commonmessages.Money{CurrencyCode: "USD", Units: 10, Nanos: 450000000}}}})
	expectedMsg := ryinterface.DomainTransferRequest{
		Name:           data.Name,
		Pw:             data.Pw,
		Period:         &data.TransferPeriod,
		PeriodUnit:     &periodUnit,
		RegistrantRoid: nil,
		Extensions:     map[string]*anypb.Any{"fee": expectedExtension},
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

	handler := service.DomainTransferInRequestHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}
