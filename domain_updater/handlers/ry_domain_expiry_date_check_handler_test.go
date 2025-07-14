package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/suite"
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
	"google.golang.org/protobuf/types/known/timestamppb"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

const ExpiryDateInSeconds int64 = 1640995200 // 2022-01-01T00:00:00Z in Unix time

func TestRyDomainExpiryDateCheckTestSuite(t *testing.T) {
	suite.Run(t, new(RyDomainExpiryDateCheckTestSuite))
}

type RyDomainExpiryDateCheckTestSuite struct {
	suite.Suite
	db     database.Database
	mb     *mocks.MockMessageBus
	s      *mocks.MockMessageBusServer
	tracer *oteltrace.Tracer
}

func (suite *RyDomainExpiryDateCheckTestSuite) SetupSuite() {
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

func (suite *RyDomainExpiryDateCheckTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertTestDomain(db database.Database, name string) (domain *model.Domain, err error) {
	tx := db.GetDB()

	var tenantCustomerID string
	err = tx.Table("v_tenant_customer").Select("id").Where("tenant_name = ?", "opensrs").Scan(&tenantCustomerID).Error
	if err != nil {
		return
	}

	var accreditationTldID *string
	err = tx.Table("accreditation_tld").Select("id").Scan(&accreditationTldID).Error
	if err != nil {
		return
	}

	createdDate := time.Unix(ExpiryDateInSeconds, 0)
	expiryDate := createdDate.AddDate(1, 0, 0)

	domain = &model.Domain{
		Name:               name,
		TenantCustomerID:   tenantCustomerID,
		AccreditationTldID: accreditationTldID,
		RyCreatedDate:      createdDate,
		RyExpiryDate:       expiryDate,
		ExpiryDate:         expiryDate,
	}

	err = tx.Create(domain).Error

	return
}

func insertProvisionDomainRenewTest(db database.Database, domain *model.Domain) (id string, err error) {
	tx := db.GetDB()

	var accreditationID string
	err = tx.Table("accreditation_tld").Select("accreditation_id").Where("id = ?", domain.AccreditationTldID).Scan(&accreditationID).Error
	if err != nil {
		return
	}

	err = tx.Raw(
		"INSERT INTO provision_domain_renew (accreditation_id, tenant_customer_id, domain_id, domain_name, current_expiry_date, status_id) VALUES (?,?,?,?,?,?) RETURNING id",
		accreditationID,
		domain.TenantCustomerID,
		domain.ID,
		domain.Name,
		domain.RyExpiryDate,
		db.GetProvisionStatusId("pending"),
	).Scan(&id).Error

	return
}

func insertRyDomainExpiryDateCheckTestJob(db database.Database, period int, expiryDate time.Time) (job *model.Job, err error) {
	tx := db.GetDB()

	domain, err := insertTestDomain(db, fmt.Sprintf("example%s.help", uuid.New().String()))
	if err != nil {
		return
	}

	provisionDomainRenewId, err := insertProvisionDomainRenewTest(db, domain)
	if err != nil {
		return
	}

	data := &types.DomainRenewData{
		Name:                   domain.Name,
		Period:                 types.ToPointer(uint32(period)),
		ExpiryDate:             &expiryDate,
		ProvisionDomainRenewId: provisionDomainRenewId,
		TenantCustomerId:       domain.TenantCustomerID,
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
			RegistrarID:          "test_registrarId",
		},
	}

	serializedData, err := json.Marshal(data)
	if err != nil {
		return
	}

	var jobId string
	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, domain.TenantCustomerID, "setup_domain_renew", "0268f162-5d83-44d2-894a-ab7578c498fb", serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)

	return
}

func (suite *RyDomainExpiryDateCheckTestSuite) TestRyDomainExpiryDateCheckHandler() {
	expectedContext := context.Background()

	testCases := []struct {
		name              string
		period            int
		expiryDate        time.Time
		msg               *ryinterface.DomainInfoResponse
		expectedJobStatus string
		expectedJobResult string
	}{
		{
			name:       "Domain does not belong to the registrar",
			period:     1,
			expiryDate: time.Now(),
			msg: &ryinterface.DomainInfoResponse{
				ExpiryDate: timestamppb.Now(),
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess:  true,
					EppCode:    types.EppCode.Success,
					EppMessage: "",
				},
				Clid: "test_registrarId2",
			},
			expectedJobStatus: "failed",
			expectedJobResult: "Domain does not belong to the registrar",
		},
		{
			name:       "Status prohibits operation",
			period:     1,
			expiryDate: time.Now(),
			msg: &ryinterface.DomainInfoResponse{
				ExpiryDate: timestamppb.Now(),
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess:  true,
					EppCode:    types.EppCode.Success,
					EppMessage: "",
				},
				Clid: "test_registrarId",
				Statuses: []string{
					types.EPPStatusCode.ClientRenewProhibited,
					types.EPPStatusCode.ServerRenewProhibited,
				},
			},
			expectedJobStatus: "failed",
			expectedJobResult: "Status prohibits operation",
		},
		{
			name:       "Domain expiry dates have day/month mismatch",
			period:     1,
			expiryDate: time.Now().AddDate(0, 0, 6),
			msg: &ryinterface.DomainInfoResponse{
				ExpiryDate: timestamppb.Now(),
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess:  true,
					EppCode:    types.EppCode.Success,
					EppMessage: "",
				},
				Clid: "test_registrarId",
			},
			expectedJobStatus: "failed",
			expectedJobResult: "Domain expiry dates have day/month mismatch between registry and database",
		},
		{
			name:       "Domain expiry dates are equal",
			period:     1,
			expiryDate: time.Now(),
			msg: &ryinterface.DomainInfoResponse{
				ExpiryDate: timestamppb.Now(),
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess:  true,
					EppCode:    types.EppCode.Success,
					EppMessage: "",
				},
				Clid: "test_registrarId",
			},
			expectedJobStatus: "completed",
			expectedJobResult: "",
		},
		{
			name:       "Domain expiry years gap is equal to the requested period",
			period:     1,
			expiryDate: time.Now(),
			msg: &ryinterface.DomainInfoResponse{
				ExpiryDate: timestamppb.New(time.Now().AddDate(1, 0, 0)),
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess:  true,
					EppCode:    types.EppCode.Success,
					EppMessage: "",
				},
				Clid: "test_registrarId",
			},
			expectedJobStatus: "completed",
			expectedJobResult: "",
		},
		{
			name:       "Domain expiry years gap is less than the requested period",
			period:     2,
			expiryDate: time.Now(),
			msg: &ryinterface.DomainInfoResponse{
				ExpiryDate: timestamppb.New(time.Now().AddDate(1, 0, 0)),
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess:  true,
					EppCode:    types.EppCode.Success,
					EppMessage: "",
				},
				Clid: "test_registrarId",
			},
			expectedJobStatus: "completed",
			expectedJobResult: "",
		},
		{
			name:       "Domain expiry years gap is greater than the requested period",
			period:     1,
			expiryDate: time.Now(),
			msg: &ryinterface.DomainInfoResponse{
				ExpiryDate: timestamppb.New(time.Now().AddDate(3, 0, 0)),
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess:  true,
					EppCode:    types.EppCode.Success,
					EppMessage: "",
				},
				Clid: "test_registrarId",
			},
			expectedJobStatus: "completed",
			expectedJobResult: "",
		},
		{
			name:       "Database expiry date is greater than registry expiry date. Gap < zero",
			period:     1,
			expiryDate: time.Now().AddDate(3, 0, 0),
			msg: &ryinterface.DomainInfoResponse{
				ExpiryDate: timestamppb.Now(),
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess:  true,
					EppCode:    types.EppCode.Success,
					EppMessage: "",
				},
				Clid: "test_registrarId",
			},
			expectedJobStatus: "completed",
			expectedJobResult: "",
		},
	}

	for _, tc := range testCases {
		suite.Run(tc.name, func() {
			job, err := insertRyDomainExpiryDateCheckTestJob(suite.db, tc.period, tc.expiryDate)
			suite.NoError(err, "Failed to insert test job")

			err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
			suite.NoError(err, "Failed to update test job")

			envelope := &message.TcWire{CorrelationId: job.ID}

			service := NewWorkerService(suite.mb, suite.db, suite.tracer)

			suite.s = &mocks.MockMessageBusServer{}
			suite.s.On("Context").Return(expectedContext)
			suite.s.On("Headers").Return(nil)
			suite.s.On("Envelope").Return(envelope)

			handler := service.RyDomainInfoRouter
			err = handler(suite.s, tc.msg)
			suite.NoError(err, types.LogMessages.HandleMessageFailed)

			job, err = suite.db.GetJobById(expectedContext, job.ID, false)
			suite.NoError(err, "Failed to fetch updated job")

			suite.Equal(tc.expectedJobStatus, *job.Info.JobStatusName)

			if job.ResultMessage != nil {
				suite.Equal(tc.expectedJobResult, *job.ResultMessage)
			}

			suite.s.AssertExpectations(suite.T())
		})
	}
}
