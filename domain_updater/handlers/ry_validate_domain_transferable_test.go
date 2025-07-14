package handlers

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/timestamppb"

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

func TestRyValidateDomainTransferableTestSuite(t *testing.T) {
	suite.Run(t, new(RyValidateDomainTransferableTestSuite))
}

type RyValidateDomainTransferableTestSuite struct {
	suite.Suite
	db database.Database
	mb *mocks.MockMessageBus
	s  *mocks.MockMessageBusServer
	t  *oteltrace.Tracer
}

func (suite *RyValidateDomainTransferableTestSuite) SetupSuite() {
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

func (suite *RyValidateDomainTransferableTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertValidateDomainTransferableTestJob(db database.Database) (job *model.Job, data *types.DomainTransferValidationData, err error) {
	tx := db.GetDB()

	//get a tenant id (doesn't matter which)
	//automatically generated when db is brought up
	var id string
	err = tx.Table("tenant_customer").Select("id").Scan(&id).Error
	if err != nil {
		return
	}

	data = &types.DomainTransferValidationData{
		Name:             "test_domain.com",
		OrderItemPlanId:  uuid.New().String(),
		TenantCustomerId: id,
		Accreditation: types.Accreditation{
			IsProxy:           false,
			AccreditationName: accreditationName,
		},
		DomainMaxLifetime: uint32(10),
		TransferPeriod:    uint32(1),
	}

	serializedData, _ := json.Marshal(data)

	var jobId string
	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, id, "validate_domain_transferable", data.OrderItemPlanId, serializedData).Scan(&jobId).Error

	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)

	return
}

func (suite *RyValidateDomainTransferableTestSuite) TestRyDomainValidateTransferableHandler() {
	expectedContext := context.Background()

	testCases := []struct {
		name              string
		msg               *rymessages.DomainInfoResponse
		expectedJobStatus string
		expectedJobResult string
	}{
		{
			name: "successful info response",
			msg: &rymessages.DomainInfoResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess:  true,
					EppCode:    types.EppCode.Success,
					EppMessage: "",
				},
				Statuses: []string{
					types.EPPStatusCode.Ok,
				},
				Clid: "test-registrar",
			},
			expectedJobStatus: "completed",
			expectedJobResult: "",
		},
		{
			name: "successful info response with client prohibited status",
			msg: &rymessages.DomainInfoResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess:  true,
					EppCode:    types.EppCode.Success,
					EppMessage: "",
				},
				Statuses: []string{
					types.EPPStatusCode.ClientTransferProhibited,
				},
				Clid: "test-registrar",
			},
			expectedJobStatus: "failed",
			expectedJobResult: "Domain is not transferable",
		},
		{
			name: "successful info response with server prohibited status",
			msg: &rymessages.DomainInfoResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess:  true,
					EppCode:    types.EppCode.Success,
					EppMessage: "",
				},
				Statuses: []string{
					types.EPPStatusCode.ServerTransferProhibited,
				},
				Clid: "test-registrar",
			},
			expectedJobStatus: "failed",
			expectedJobResult: "Domain is not transferable",
		},
		{
			name: "successful info response with multiple statuses",
			msg: &rymessages.DomainInfoResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess:  true,
					EppCode:    types.EppCode.Success,
					EppMessage: "",
				},
				Statuses: []string{
					types.EPPStatusCode.Ok,
					types.EPPStatusCode.AutoRenewPeriod,
					types.EPPStatusCode.ServerTransferProhibited,
				},
				Clid: "test-registrar",
			},
			expectedJobStatus: "failed",
			expectedJobResult: "Domain is not transferable",
		},
		{
			name: "successful info response with unsuccessful status epp code",
			msg: &rymessages.DomainInfoResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess:  true,
					EppCode:    types.EppCode.Pending,
					EppMessage: "Domain transfer validation failed",
				},
				Statuses: []string{},
				Clid:     "test-registrar",
			},
			expectedJobStatus: "failed",
			expectedJobResult: "Domain transfer validation failed",
		},
		{
			name: "unsuccessful info response",
			msg: &rymessages.DomainInfoResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess:  false,
					EppCode:    types.EppCode.Pending,
					EppMessage: "Domain transfer validation failed",
				},
				Statuses: []string{},
				Clid:     "test-registrar",
			},
			expectedJobStatus: "failed",
			expectedJobResult: "Domain transfer validation failed",
		},
		{
			name: "expiry date exceeds maximum allowed lifetime",
			msg: &rymessages.DomainInfoResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess:  true,
					EppCode:    types.EppCode.Success,
					EppMessage: "",
				},
				ExpiryDate: timestamppb.New(time.Now().AddDate(10, 0, 0)),
				Statuses:   []string{},
				Clid:       "test-registrar",
			},
			expectedJobStatus: "failed",
			expectedJobResult: "Domain transfer period exceeds maximum allowed lifetime",
		},
	}

	for _, tc := range testCases {
		suite.Run(tc.name, func() {
			job, _, err := insertValidateDomainTransferableTestJob(suite.db)
			suite.NoError(err, "Failed to insert test job")

			err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
			suite.NoError(err, "Failed to update test job")

			envelope := &message.TcWire{CorrelationId: job.ID}

			service := NewWorkerService(suite.mb, suite.db, suite.t)

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
