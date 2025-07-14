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
	"github.com/tucowsinc/tdp-messages-go/message/job"
	rymessages "github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	config "github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

func TestValidateDomainCheckTestSuite(t *testing.T) {
	suite.Run(t, new(ValidateDomainCheckTestSuite))
}

type ValidateDomainCheckTestSuite struct {
	suite.Suite
	db     database.Database
	mb     *mocks.MockMessageBus
	s      *mocks.MockMessageBusServer
	tracer *oteltrace.Tracer
}

func (suite *ValidateDomainCheckTestSuite) SetupSuite() {
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

func (suite *ValidateDomainCheckTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertValidateDomainCheckTestJob(db database.Database, isPremiumDomainEnabled bool) (jobId string, data *types.DomainCheckValidationData, err error) {
	tx := db.GetDB()

	//get a tenant id (doesn't matter which)
	//automatically generated when db is brought up
	var id string
	err = tx.Table("tenant_customer").Select("id").Scan(&id).Error
	if err != nil {
		return
	}

	period := uint32(1)
	data = &types.DomainCheckValidationData{
		Name:             "test_domain.com",
		OrderItemPlanId:  uuid.New().String(),
		TenantCustomerId: id,
		Accreditation: types.Accreditation{
			IsProxy:           false,
			AccreditationName: accreditationName,
		},
		OrderType:            "create",
		PremiumDomainEnabled: isPremiumDomainEnabled,
		Period:               &period,
	}
	if isPremiumDomainEnabled {
		data.Price = &types.OrderPrice{
			Amount:   1045,
			Fraction: 100,
			Currency: "USD",
		}
	}

	serializedData, _ := json.Marshal(data)

	var jobType string
	switch isPremiumDomainEnabled {
	case true:
		jobType = "validate_domain_premium"
	case false:
		jobType = "validate_domain_available"
	}

	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, id, jobType, data.OrderItemPlanId, serializedData).Scan(&jobId).Error

	return
}

func (suite *ValidateDomainCheckTestSuite) TestValidateDomainCheckHandlerHandler() {
	expectedCurrency := "USD"
	expectedPeriod := uint32(1)
	expectedPeriodUnit := commonmessages.PeriodUnit_YEAR
	expectedOperation := rymessages.DomainOperationFee_REGISTRATION

	testCases := []struct {
		name                   string
		isPremiumDomainEnabled bool
	}{
		{
			name:                   "domain check with fee extension",
			isPremiumDomainEnabled: true,
		},
		{
			name:                   "domain check without fee extension",
			isPremiumDomainEnabled: false,
		},
	}

	for _, tc := range testCases {
		suite.SetupTest()
		jobId, data, err := insertValidateDomainCheckTestJob(suite.db, tc.isPremiumDomainEnabled)
		suite.NoError(err, "Failed to insert test job")

		msg := &job.Notification{
			JobId:          jobId,
			Type:           "validate_domain_premium",
			Status:         "submitted",
			ReferenceId:    data.OrderItemPlanId,
			ReferenceTable: "order_item_plan",
		}

		expectedContext := context.Background()
		expectedDestination := types.GetQueryQueue(accreditationName)

		expectedDomainNames := []string{data.Name}

		expectedMsg := rymessages.DomainCheckRequest{
			Names: expectedDomainNames,
		}

		if tc.isPremiumDomainEnabled {
			feeExtension, err := anypb.New(&extension.FeeCheckRequest{
				Operation:  &expectedOperation,
				Names:      expectedDomainNames,
				Currency:   &expectedCurrency,
				Period:     &expectedPeriod,
				PeriodUnit: &expectedPeriodUnit,
			})
			suite.NoError(err, "Failed to create fee extension")
			expectedMsg.Extensions = map[string]*anypb.Any{"fee": feeExtension}
		}

		expectedHeaders := map[string]any{
			"reply_to":       "WorkerJobDomainProvisionUpdate",
			"correlation_id": jobId,
		}

		service := NewWorkerService(suite.mb, suite.db, suite.tracer)

		suite.mb.On("Send", expectedContext, expectedDestination, &expectedMsg, expectedHeaders).Return(nil)
		suite.s.On("MessageBus").Return(suite.mb)
		suite.s.On("Headers").Return(expectedHeaders)
		suite.s.On("Context").Return(expectedContext)

		handler := service.ValidateDomainCheckHandler
		err = handler(suite.s, msg)
		suite.NoError(err, types.LogMessages.HandleMessageFailed)

		suite.mb.AssertExpectations(suite.T())
		suite.s.AssertExpectations(suite.T())
	}
}
