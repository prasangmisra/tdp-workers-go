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

func TestRyValidateDomainCheckTestSuite(t *testing.T) {
	suite.Run(t, new(RyValidateDomainCheckTestSuite))
}

type RyValidateDomainCheckTestSuite struct {
	suite.Suite
	db database.Database
	mb *mocks.MockMessageBus
	s  *mocks.MockMessageBusServer
	t  *oteltrace.Tracer
}

func (suite *RyValidateDomainCheckTestSuite) SetupSuite() {
	cfg, err := config.LoadConfiguration("../../.env")
	suite.NoError(err, "Failed to read config from .env")

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

func (suite *RyValidateDomainCheckTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertValidateDomainCheckTestJob(db database.Database, isPremiumOperation bool, isPremiumDomainEnabled bool) (job *model.Job, data types.DomainCheckValidationData, err error) {
	tx := db.GetDB()

	//get a tenant id (doesn't matter which)
	//automatically generated when db is brought up
	var id string
	err = tx.Table("tenant_customer").Select("id").Scan(&id).Error
	if err != nil {
		return
	}

	data = types.DomainCheckValidationData{
		Name:             "test_domain.com",
		OrderItemPlanId:  uuid.New().String(),
		TenantCustomerId: id,
		Accreditation: types.Accreditation{
			IsProxy:           false,
			AccreditationName: accreditationName,
		},
		OrderType:            "create",
		PremiumOperation:     &isPremiumOperation,
		PremiumDomainEnabled: isPremiumDomainEnabled,
		Price: &types.OrderPrice{
			Amount:   1045,
			Fraction: 100,
			Currency: "USD",
		},
	}

	serializedData, _ := json.Marshal(data)

	var jobId string
	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, id, "validate_domain_premium", data.OrderItemPlanId, serializedData).Scan(&jobId).Error

	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)

	return
}

func (suite *RyValidateDomainCheckTestSuite) TestRyDomainValidateAvailabilityHandler() {
	expectedContext := context.Background()

	description := "renewal Premium Domain Fee"
	pricingTier := "premium tier 4"

	testCases := []struct {
		name                   string
		isSuccess              bool
		eppCode                int32
		domains                []*rymessages.DomainAvailResponse
		expectedJobStatus      string
		expectedJobResult      *string
		isPremiumOperation     bool
		isPremiumDomainEnabled bool
	}{
		{
			name:      "successful check",
			isSuccess: true,
			eppCode:   1000,
			domains: []*rymessages.DomainAvailResponse{{
				Name:        "test_domain.com",
				PricingTier: &pricingTier,
				Fees: []*rymessages.DomainOperationFee{{
					Description: &description,
					Price:       &commonmessages.Money{CurrencyCode: "USD", Units: 10, Nanos: 450000000},
					Operation:   rymessages.DomainOperationFee_REGISTRATION,
				}},
				IsAvailable: true,
			}},
			expectedJobStatus:      "completed",
			isPremiumOperation:     true,
			isPremiumDomainEnabled: true,
		},
		{
			name:      "invalid price",
			isSuccess: true,
			eppCode:   1000,
			domains: []*rymessages.DomainAvailResponse{{
				Name:        "test_domain.com",
				PricingTier: &pricingTier,
				Fees: []*rymessages.DomainOperationFee{{
					Description: &description,
					Price:       &commonmessages.Money{CurrencyCode: "USD", Units: 101, Nanos: 450000000},
				}},
				IsAvailable: true,
			}},
			expectedJobStatus:      "failed",
			expectedJobResult:      types.ToPointer("price mismatch"),
			isPremiumOperation:     true,
			isPremiumDomainEnabled: true,
		},
		{
			name:      "not premium operation",
			isSuccess: true,
			eppCode:   1000,
			domains: []*rymessages.DomainAvailResponse{{
				Name:        "test_domain.com",
				PricingTier: &pricingTier,
				IsAvailable: true,
			}},
			expectedJobStatus:      "completed",
			isPremiumOperation:     false,
			isPremiumDomainEnabled: true,
		},
		{
			name:      "premium domain not enabled",
			isSuccess: true,
			eppCode:   1000,
			domains: []*rymessages.DomainAvailResponse{{
				Name:        "test_domain.com",
				PricingTier: &pricingTier,
				IsAvailable: true,
			}},
			expectedJobStatus:      "failed",
			expectedJobResult:      types.ToPointer("premium domain not enabled"),
			isPremiumDomainEnabled: false,
		},
		{
			name:      "domain not premium",
			isSuccess: true,
			eppCode:   1000,
			domains: []*rymessages.DomainAvailResponse{{
				Name:        "test_domain.com",
				IsAvailable: true,
			}},
			expectedJobStatus: "completed",
		},
		{
			name:              "invalid check response",
			isSuccess:         true,
			eppCode:           1000,
			domains:           []*rymessages.DomainAvailResponse{},
			expectedJobStatus: "failed",
			expectedJobResult: types.ToPointer("domain validation failed"),
		},
		{
			name:              "failed check response",
			isSuccess:         false,
			eppCode:           2400,
			domains:           []*rymessages.DomainAvailResponse{},
			expectedJobStatus: "failed",
			expectedJobResult: types.ToPointer("failed to check domain"),
		},
		{
			name:      "domain not available",
			isSuccess: true,
			eppCode:   1000,
			domains: []*rymessages.DomainAvailResponse{{
				Name:        "test_domain.com",
				IsAvailable: false,
			}},
			expectedJobStatus: "failed",
			expectedJobResult: types.ToPointer("domain is not available"),
		},
	}

	for _, tc := range testCases {
		suite.Run(tc.name, func() {
			job, _, err := insertValidateDomainCheckTestJob(suite.db, tc.isPremiumOperation, tc.isPremiumDomainEnabled)
			suite.NoError(err, "Failed to insert test job")

			err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
			suite.NoError(err, "Failed to update test job")

			envelope := &message.TcWire{CorrelationId: job.ID}

			msg := &rymessages.DomainCheckResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess: tc.isSuccess,
					EppCode:   tc.eppCode,
				},
				Domains: tc.domains,
			}

			if tc.expectedJobResult != nil {
				msg.RegistryResponse.EppMessage = *tc.expectedJobResult
			}
			service := NewWorkerService(suite.mb, suite.db, suite.t)

			suite.s = &mocks.MockMessageBusServer{}
			suite.s.On("Context").Return(expectedContext)
			suite.s.On("Headers").Return(nil)
			suite.s.On("Envelope").Return(envelope)

			handler := service.RyDomainCheckHandler
			err = handler(suite.s, msg)
			suite.NoError(err, types.LogMessages.HandleMessageFailed)

			job, err = suite.db.GetJobById(expectedContext, job.ID, false)
			suite.NoError(err, "Failed to fetch updated job")

			suite.Equal(tc.expectedJobStatus, *job.Info.JobStatusName)

			if job.ResultMessage != nil {
				suite.Equal(*tc.expectedJobResult, *job.ResultMessage)
			}

			suite.s.AssertExpectations(suite.T())
		})
	}
}
