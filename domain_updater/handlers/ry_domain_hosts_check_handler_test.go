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
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

func TestRyDomainHostsCheckTestSuite(t *testing.T) {
	suite.Run(t, new(RyDomainHostsCheckTestSuite))
}

type RyDomainHostsCheckTestSuite struct {
	suite.Suite
	db     database.Database
	mb     *mocks.MockMessageBus
	s      *mocks.MockMessageBusServer
	tracer *oteltrace.Tracer
}

func (suite *RyDomainHostsCheckTestSuite) SetupSuite() {
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

func (suite *RyDomainHostsCheckTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertRyDomainHostsCheckTestJob(db database.Database) (job *model.Job, err error) {
	tx := db.GetDB()

	domain, err := insertTestDomain(db, fmt.Sprintf("example%s.help", uuid.New().String()))
	if err != nil {
		return
	}

	provisionDomainDeleteId, err := insertProvisionDomainDeleteTest(db, domain)
	if err != nil {
		return
	}

	metadata := map[string]interface{}{
		"order_id": "test_order_id",
	}

	data := &types.DomainDeleteData{
		Name:                    domain.Name,
		ProvisionDomainDeleteId: provisionDomainDeleteId,
		TenantCustomerId:        domain.TenantCustomerID,
		Metadata:                metadata,
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
	err = tx.Raw(sql, domain.TenantCustomerID, "setup_domain_delete", "0268f162-5d83-44d2-894a-ab7578c498fb", serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)

	return
}

func (suite *RyDomainHostsCheckTestSuite) TestRyDomainHostsCheckHandler() {
	expectedContext := context.Background()

	testCases := []struct {
		name              string
		period            int
		Delete            time.Time
		msg               *ryinterface.DomainInfoResponse
		expectedJobStatus string
		expectedJobResult string
	}{
		{
			name: "Domain does not belong to the registrar",
			msg: &ryinterface.DomainInfoResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess: true,
					EppCode:   types.EppCode.Success,
				},
				Clid: "test_registrarId2",
			},
			expectedJobStatus: "failed",
			expectedJobResult: "Domain does not belong to the registrar",
		},
		{
			name: "Domain info has hosts",
			msg: &ryinterface.DomainInfoResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess: true,
					EppCode:   types.EppCode.Success,
				},
				Clid:  "test_registrarId",
				Hosts: []string{"ns1.example.com", "ns2.example.com"},
			},
			expectedJobStatus: "completed",
			expectedJobResult: "",
		},
		{
			name: "Domain info has no hosts",
			msg: &ryinterface.DomainInfoResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess: true,
					EppCode:   types.EppCode.Success,
				},
				Clid: "test_registrarId",
			},
			expectedJobStatus: "completed",
			expectedJobResult: "",
		},
		{
			name: "Domain doesn't exist",
			msg: &ryinterface.DomainInfoResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess: false,
					EppCode:   types.EppCode.ObjectDoesNotExist,
				},
			},
			expectedJobStatus: "completed",
			expectedJobResult: "",
		},
		{
			name: "Failed getting domain info from registry",
			msg: &ryinterface.DomainInfoResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess:  false,
					EppCode:    types.EppCode.ObjectAssociationProhibitsOperation,
					EppMessage: "Failed getting domain info from registry",
				},
			},
			expectedJobStatus: "failed",
			expectedJobResult: "Failed getting domain info from registry",
		},
	}

	for _, tc := range testCases {
		suite.Run(tc.name, func() {
			job, err := insertRyDomainHostsCheckTestJob(suite.db)
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
