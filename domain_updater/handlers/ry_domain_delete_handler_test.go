package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/anypb"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message"
	commonmessages "github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"

	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

func TestRyDomainDeleteTestSuite(t *testing.T) {
	suite.Run(t, new(RyDomainDeleteTestSuite))
}

type RyDomainDeleteTestSuite struct {
	suite.Suite
	db     database.Database
	mb     *mocks.MockMessageBus
	s      *mocks.MockMessageBusServer
	tracer *oteltrace.Tracer
}

func (suite *RyDomainDeleteTestSuite) SetupSuite() {
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

func (suite *RyDomainDeleteTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertProvisionDomainDeleteTest(db database.Database, domain *model.Domain) (id string, err error) {
	tx := db.GetDB()

	var accreditationID string
	err = tx.Table("accreditation_tld").Select("accreditation_id").Where("id = ?", domain.AccreditationTldID).Scan(&accreditationID).Error
	if err != nil {
		return
	}

	err = tx.Raw(
		"INSERT INTO provision_domain_delete (accreditation_id, tenant_customer_id, domain_id, domain_name, status_id) VALUES (?,?,?,?,?) RETURNING id",
		accreditationID,
		domain.TenantCustomerID,
		domain.ID,
		domain.Name,
		db.GetProvisionStatusId("pending"),
	).Scan(&id).Error

	return
}

func insertRyDomainDeleteTestJob(db database.Database, addGracePeriod bool) (job *model.Job, domainName string, err error) {
	tx := db.GetDB()

	domain, err := insertTestDomain(db, fmt.Sprintf("example%s.help", uuid.New().String()))
	if err != nil {
		return
	}
	domainName = domain.Name

	if addGracePeriod {
		err = tx.Exec(`INSERT INTO domain_rgp_status (
		domain_id,
		status_id
	) VALUES (
		?,
		tc_id_from_name('rgp_status', 'add_grace_period')
	)`, domain.ID).Error
		if err != nil {
			return
		}
	}

	provisionDomainDeleteId, err := insertProvisionDomainDeleteTest(db, domain)
	if err != nil {
		return
	}

	data := &types.DomainDeleteData{
		Name:                    domain.Name,
		ProvisionDomainDeleteId: provisionDomainDeleteId,
		TenantCustomerId:        domain.TenantCustomerID,
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
	err = tx.Raw(sql, data.TenantCustomerId, "provision_domain_delete", provisionDomainDeleteId, serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)

	return
}

func GetProvisionDomainDelete(db database.Database, id string) (pdd model.ProvisionDomainDelete, err error) {
	tx := db.GetDB()

	sql := `SELECT * FROM provision_domain_delete WHERE id = ?`
	err = tx.Raw(sql, id).Scan(&pdd).Error
	return
}

func (suite *RyDomainDeleteTestSuite) TestRyDomainDeleteHandler() {
	expectedContext := context.Background()

	job, _, err := insertRyDomainDeleteTestJob(suite.db, false)
	suite.NoError(err, "Failed to insert test job")

	err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to update test job")

	envelope := &message.TcWire{CorrelationId: job.ID}

	msg := &ryinterface.DomainDeleteResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  true,
			EppCode:    1000,
			EppMessage: "",
		},
	}

	service := NewWorkerService(suite.mb, suite.db, suite.tracer)

	suite.s.On("Context").Return(expectedContext)
	suite.s.On("Headers").Return(nil)
	suite.s.On("Envelope").Return(envelope)

	handler := service.RyDomainDeleteHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)
}

func (suite *RyDomainDeleteTestSuite) TestRyDomainDeleteHandlerWithPendingResponse() {
	expectedContext := context.Background()

	job, _, err := insertRyDomainDeleteTestJob(suite.db, false)
	suite.NoError(err, "Failed to insert test job")

	err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to update test job")

	envelope := &message.TcWire{CorrelationId: job.ID}

	msg := &ryinterface.DomainDeleteResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  true,
			EppCode:    1001,
			EppMessage: "",
			EppCltrid:  "ABC-123",
		},
	}

	service := NewWorkerService(suite.mb, suite.db, suite.tracer)

	suite.s.On("Context").Return(expectedContext)
	suite.s.On("Headers").Return(nil)
	suite.s.On("Envelope").Return(envelope)

	handler := service.RyDomainDeleteHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)
}

func (suite *RyDomainDeleteTestSuite) TestProcessRyDomainDeleteResponse() {
	expectedContext := context.Background()

	testCases := []struct {
		name                   string
		msg                    *ryinterface.DomainDeleteResponse
		expectedRedemptionFlag bool
		expectedJobStatus      string
	}{
		{
			name: "Failed to fetch domain from database",
			msg: &ryinterface.DomainDeleteResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess: true,
					EppCode:   types.EppCode.Success,
				},
			},
			expectedRedemptionFlag: false,
			expectedJobStatus:      "failed",
		},
		{
			name: "Domain is not in add grace period",
			msg: &ryinterface.DomainDeleteResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess: true,
					EppCode:   types.EppCode.Success,
				},
			},
			expectedRedemptionFlag: true,
			expectedJobStatus:      "completed",
		},
		{
			name: "Domain delete returned EppCode 1000",
			msg: &ryinterface.DomainDeleteResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess: true,
					EppCode:   types.EppCode.Success,
				},
			},
			expectedRedemptionFlag: false,
			expectedJobStatus:      "completed",
		},
		{
			name: "Unexpected error fetching domain info from registry",
			msg: &ryinterface.DomainDeleteResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess: true,
					EppCode:   types.EppCode.Pending,
				},
			},
			expectedRedemptionFlag: false,
			expectedJobStatus:      "failed",
		},
		{
			name: "Domain object does not exist",
			msg: &ryinterface.DomainDeleteResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess: true,
					EppCode:   types.EppCode.Pending,
				},
			},
			expectedRedemptionFlag: false,
			expectedJobStatus:      "completed",
		},
		{
			name: "RGP extension is redemptionPeriod",
			msg: &ryinterface.DomainDeleteResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess: true,
					EppCode:   types.EppCode.Pending,
				},
			},
			expectedRedemptionFlag: true,
			expectedJobStatus:      "completed",
		},
		{
			name: "Domain status is pendingDelete",
			msg: &ryinterface.DomainDeleteResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess: true,
					EppCode:   types.EppCode.Pending,
				},
			},
			expectedRedemptionFlag: false,
			expectedJobStatus:      "completed",
		},
		{
			name: "Failed to determine domain status",
			msg: &ryinterface.DomainDeleteResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess: true,
					EppCode:   types.EppCode.Pending,
				},
			},
			expectedRedemptionFlag: false,
			expectedJobStatus:      "failed",
		},
		{
			name: "Failed to fetch domain info from registry",
			msg: &ryinterface.DomainDeleteResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess: true,
					EppCode:   types.EppCode.Pending,
				},
			},
			expectedRedemptionFlag: false,
			expectedJobStatus:      "failed",
		},
	}

	for i, tc := range testCases {
		suite.Run(tc.name, func() {
			suite.T().Logf("\033[34mRunning test case #%d : (%s)\033[0m", i+1, tc.name)

			suite.SetupTest()

			addGracePeriod := true
			if tc.name == "Domain is not in add grace period" {
				addGracePeriod = false
			}

			job, domain, err := insertRyDomainDeleteTestJob(suite.db, addGracePeriod)
			suite.NoError(err, "Failed to insert test job")

			err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
			suite.NoError(err, "Failed to update test job")

			envelope := &message.TcWire{CorrelationId: job.ID}

			service := NewWorkerService(suite.mb, suite.db, suite.tracer)

			suite.s = &mocks.MockMessageBusServer{}
			suite.s.On("Context").Return(expectedContext)
			suite.s.On("Headers").Return(nil)
			suite.s.On("Envelope").Return(envelope)

			switch tc.name {
			case "Failed to fetch domain from database":
				suite.db.GetDB().Exec("DELETE FROM domain WHERE name = ?", domain)
			case "Unexpected error fetching domain info from registry":
				suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainInfoRequest"), mock.Anything).
					Return(nil, fmt.Errorf("unexpected error fetching domain info from registry"))
			case "Domain object does not exist":
				suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainInfoRequest"), mock.Anything).
					Return(messagebus.RpcResponse{
						Message: &ryinterface.DomainInfoResponse{
							Name: domain,
							RegistryResponse: &commonmessages.RegistryResponse{
								IsSuccess: false,
								EppCode:   types.EppCode.ObjectDoesNotExist,
							},
						}}, nil)
			case "RGP extension is redemptionPeriod":
				expectedExtension, _ := anypb.New(&extension.RgpInfoResponse{
					Rgpstatus: types.RgpStatus.RedemptionPeriod,
				})

				suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainInfoRequest"), mock.Anything).
					Return(messagebus.RpcResponse{
						Message: &ryinterface.DomainInfoResponse{
							Name: domain,
							RegistryResponse: &commonmessages.RegistryResponse{
								IsSuccess: true,
								EppCode:   types.EppCode.Success,
							},
							Extensions: map[string]*anypb.Any{"rgp": expectedExtension},
						}}, nil)
			case "Domain status is pendingDelete":
				suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainInfoRequest"), mock.Anything).
					Return(messagebus.RpcResponse{
						Message: &ryinterface.DomainInfoResponse{
							Name: domain,
							RegistryResponse: &commonmessages.RegistryResponse{
								IsSuccess: true,
								EppCode:   types.EppCode.Success,
							},
							Statuses: []string{types.EPPStatusCode.PendingDelete},
						}}, nil)
			case "Failed to determine domain status":
				suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainInfoRequest"), mock.Anything).
					Return(messagebus.RpcResponse{
						Message: &ryinterface.DomainInfoResponse{
							Name: domain,
							RegistryResponse: &commonmessages.RegistryResponse{
								IsSuccess: true,
								EppCode:   types.EppCode.Success,
							},
						}}, nil)
			case "Failed to fetch domain info from registry":
				suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainInfoRequest"), mock.Anything).
					Return(messagebus.RpcResponse{
						Message: &ryinterface.DomainInfoResponse{
							Name: domain,
							RegistryResponse: &commonmessages.RegistryResponse{
								IsSuccess: false,
								EppCode:   types.EppCode.InvalidAuthInfo,
							},
						}}, nil)
			}

			handler := service.RyDomainDeleteHandler
			err = handler(suite.s, tc.msg)
			suite.NoError(err, types.LogMessages.HandleMessageFailed)

			job, err = suite.db.GetJobById(expectedContext, job.ID, false)
			suite.NoError(err, "Failed to fetch updated job")

			suite.Equal(tc.expectedJobStatus, *job.Info.JobStatusName)

			pdd, err := GetProvisionDomainDelete(suite.db, *job.Info.ReferenceID)
			suite.NoError(err, "Failed to fetch provision domain delete")

			suite.Equal(tc.expectedRedemptionFlag, pdd.InRedemptionGracePeriod)

			suite.s.AssertExpectations(suite.T())
		})
	}
}

func (suite *RyDomainDeleteTestSuite) TestRyDomainDeleteErrResponse() {
	expectedContext := context.Background()
	// placeholder for actual epp error message
	eppErrMessage := "failed to delete domain; object does not exist"
	msg := &ryinterface.DomainDeleteResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  false,
			EppCode:    types.EppCode.ParameterPolicyError,
			EppMessage: eppErrMessage,
		},
	}

	suite.SetupTest()

	job, _, err := insertRyDomainDeleteTestJob(suite.db, false)
	suite.NoError(err, "Failed to insert test job")

	err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to update test job")

	envelope := &message.TcWire{CorrelationId: job.ID}

	service := NewWorkerService(suite.mb, suite.db, suite.tracer)

	suite.s = &mocks.MockMessageBusServer{}
	suite.s.On("Context").Return(expectedContext)
	suite.s.On("Headers").Return(nil)
	suite.s.On("Envelope").Return(envelope)

	handler := service.RyDomainDeleteHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	job, err = suite.db.GetJobById(expectedContext, job.ID, false)
	suite.NoError(err, "Failed to fetch updated job")

	suite.Equal("failed", *job.Info.JobStatusName)

	suite.Equal(eppErrMessage, *job.ResultMessage)

	suite.s.AssertExpectations(suite.T())
}
