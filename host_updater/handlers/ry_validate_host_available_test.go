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

func TestRyValidateHostAvailableTestSuite(t *testing.T) {
	suite.Run(t, new(RyValidateHostAvailableTestSuite))
}

type RyValidateHostAvailableTestSuite struct {
	suite.Suite
	db database.Database
	mb *mocks.MockMessageBus
	s  *mocks.MockMessageBusServer
	t  *oteltrace.Tracer
}

func (suite *RyValidateHostAvailableTestSuite) SetupSuite() {
	cfg, err := config.LoadConfiguration("../../.env")
	suite.NoError(err, "Failed to read config from .env")

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

func (suite *RyValidateHostAvailableTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertValidateHostAvailableTestJob(db database.Database) (job *model.Job, data *types.HostValidationData, err error) {
	tx := db.GetDB()

	//get a tenant id (doesn't matter which)
	//automatically generated when db is brought up
	var id string
	err = tx.Table("tenant_customer").Select("id").Scan(&id).Error
	if err != nil {
		return
	}

	data = &types.HostValidationData{
		HostName:         "ns1.testdomain.com",
		OrderItemPlanId:  uuid.New().String(),
		TenantCustomerId: id,
		Accreditation: types.Accreditation{
			IsProxy:           false,
			AccreditationName: accreditationName,
		},
	}

	serializedData, _ := json.Marshal(data)

	var jobId string
	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, id, "validate_host_available", data.OrderItemPlanId, serializedData).Scan(&jobId).Error

	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)

	return
}

func (suite *RyValidateHostAvailableTestSuite) TestRyDomainValidateAvailabilityHandler() {
	testCases := []struct {
		name              string
		isSuccess         bool
		eppCode           int32
		hosts             []*rymessages.HostAvailResponse
		expectedJobStatus string
		expectedJobResult *string
	}{
		{
			name:      "successful check; host available",
			isSuccess: true,
			eppCode:   1000,
			hosts: []*rymessages.HostAvailResponse{{
				Name:        "ns1.testdomain.com",
				IsAvailable: true,
			}},
			expectedJobStatus: "completed",
			expectedJobResult: nil,
		},
		{
			name:              "invalid check response",
			isSuccess:         true,
			eppCode:           1000,
			hosts:             []*rymessages.HostAvailResponse{},
			expectedJobStatus: "failed",
			expectedJobResult: types.ToPointer("host validation failed"),
		},
		{
			name:              "failed check response",
			isSuccess:         false,
			eppCode:           2400,
			hosts:             []*rymessages.HostAvailResponse{},
			expectedJobStatus: "failed",
			expectedJobResult: types.ToPointer("host validation failed"),
		},
		{
			name:      "host not available",
			isSuccess: true,
			eppCode:   1000,
			hosts: []*rymessages.HostAvailResponse{{
				Name:        "ns1.testdomain.com",
				IsAvailable: false,
			}},
			expectedJobStatus: "completed",
			expectedJobResult: types.ToPointer("host \"ns1.testdomain.com\" already exists in registry"),
		},
	}

	for _, tc := range testCases {
		suite.Run(tc.name, func() {
			job, _, err := insertValidateHostAvailableTestJob(suite.db)
			suite.NoError(err, "Failed to insert test job")

			expectedContext := context.Background()

			err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
			suite.NoError(err, "Failed to update test job")

			envelope := &message.TcWire{CorrelationId: job.ID}

			msg := &rymessages.HostCheckResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess: tc.isSuccess,
					EppCode:   tc.eppCode,
				},
				Hosts: tc.hosts,
			}

			if tc.expectedJobResult != nil {
				msg.RegistryResponse.EppMessage = *tc.expectedJobResult
			}
			service := NewWorkerService(suite.mb, suite.db, suite.t)

			suite.s = &mocks.MockMessageBusServer{}
			suite.s.On("Context").Return(expectedContext)
			suite.s.On("Headers").Return(nil)
			suite.s.On("Envelope").Return(envelope)

			handler := service.RyHostCheckHandler
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
