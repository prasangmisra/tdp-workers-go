package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	"github.com/tucowsinc/tdp-messages-go/message"
)

type RyTimeoutHandlerTestSuite struct {
	suite.Suite
	db database.Database
	s  *mocks.MockMessageBusServer
	mb *mocks.MockMessageBus
	t  *oteltrace.Tracer
}

func TestRyTimeoutHandlerTestSuite(t *testing.T) {
	suite.Run(t, new(RyTimeoutHandlerTestSuite))
}

func (suite *RyTimeoutHandlerTestSuite) SetupSuite() {
	config, err := config.LoadConfiguration("../../.env")
	suite.NoError(err, "Failed to read config from .env")

	config.LogLevel = "mute" // suppress log output
	log.Setup(config)

	config.TracingEnabled = false
	tracer, _, err := tracing.Setup(context.Background(), config)
	if err != nil {
		log.Fatal("Error setting up tracing", log.Fields{"error": err})
	}
	suite.t = tracer

	db, err := database.New(config.PostgresPoolConfig(), config.GetDBLogLevel())
	suite.NoError(err, types.LogMessages.DatabaseConnectionFailed)
	suite.db = db
}

func (suite *RyTimeoutHandlerTestSuite) SetupTest() {
	suite.s = &mocks.MockMessageBusServer{}
	suite.mb = &mocks.MockMessageBus{}
}

func insertTestJob(db database.Database, jobType string) (job *model.Job, err error) {
	tx := db.GetDB()

	domain, err := insertTestDomain(db, fmt.Sprintf("example%s.help", uuid.New().String()))
	if err != nil {
		return
	}

	var serializedData []byte
	var referenceId string
	switch jobType {
	case "provision_domain_renew":
		referenceId, err = insertProvisionDomainRenewTest(db, domain)
		if err != nil {
			return
		}

		data := types.DomainRenewData{
			Name:                   domain.Name,
			ProvisionDomainRenewId: referenceId,
			TenantCustomerId:       domain.TenantCustomerID,
			Accreditation: types.Accreditation{
				AccreditationId:   "test_accreditationId",
				AccreditationName: accreditationName,
			},
		}

		serializedData, err = json.Marshal(data)
		if err != nil {
			return
		}
	case "provision_domain_contact_update":
		referenceId = uuid.NewString()
	}

	var jobId string
	sql := `SELECT job_create(?,?,?,?)`
	err = tx.Raw(sql, domain.TenantCustomerID, jobType, referenceId, serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)

	return
}

func (suite *RyTimeoutHandlerTestSuite) TestRyTimeoutHandler() {
	expectedContext := context.Background()

	testCases := []struct {
		name              string
		jobType           string
		expectedJobStatus string
	}{
		{
			name:              "Failed to get job by id",
			jobType:           "provision_domain_renew",
			expectedJobStatus: "processing",
		},
		{
			name:              "Unsupport job type",
			jobType:           "provision_domain_contact_update",
			expectedJobStatus: "failed",
		},
	}

	for _, tc := range testCases {
		suite.Run(tc.name, func() {
			suite.SetupTest()

			job, err := insertTestJob(suite.db, tc.jobType)
			suite.NoError(err, "Failed to insert test job")

			suite.s.On("Context").Return(expectedContext)
			suite.s.On("Headers").Return(nil)

			switch tc.name {
			case "Failed to get job by id":
				suite.s.On("Envelope").Return(&message.TcWire{CorrelationId: "invalid_job_id"})
			case "Unsupport job type":
				suite.s.On("Envelope").Return(&message.TcWire{CorrelationId: job.ID})
			}

			err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
			suite.NoError(err, "Failed to update test job")

			service := NewWorkerService(suite.mb, suite.db, suite.t)

			errorResponse := &message.ErrorResponse{
				Code:    message.ErrorResponse_TIMEOUT,
				Message: "timeout error",
			}

			handler := service.RyTimeoutHandler
			handler(suite.s, errorResponse)

			job, err = suite.db.GetJobById(expectedContext, job.ID, false)
			suite.NoError(err, "Failed to get test job")

			suite.Equal(tc.expectedJobStatus, suite.db.GetJobStatusName(job.StatusID))
			suite.NoError(err, types.LogMessages.HandleMessageFailed)

			suite.s.AssertExpectations(suite.T())
		})
	}
}
