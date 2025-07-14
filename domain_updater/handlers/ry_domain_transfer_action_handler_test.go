package handlers

import (
	"context"
	"testing"

	sqlx "github.com/jmoiron/sqlx/types"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

func TestRyDomainTransferActionHandler(t *testing.T) {
	suite.Run(t, new(RyDomainTransferActionHandlerTestSuite))
}

type RyDomainTransferActionHandlerTestSuite struct {
	suite.Suite
	db *database.MockDatabase
	mb *mocks.MockMessageBus
	s  *mocks.MockMessageBusServer
	t  *oteltrace.Tracer
}

func (suite *RyDomainTransferActionHandlerTestSuite) SetupTest() {
	suite.db = &database.MockDatabase{}
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
	cfg, err := config.LoadConfiguration("../../.env")
	suite.NoError(err, "Failed to read config from .env")

	cfg.LogLevel = "mute" // suppress log output
	log.Setup(cfg)

	cfg.TracingEnabled = false
	tracer, _, err := tracing.Setup(context.Background(), cfg)
	if err != nil {
		log.Fatal("Error setting up tracing", log.Fields{"error": err})
	}
	suite.t = tracer
}

func (suite *RyDomainTransferActionHandlerTestSuite) TestRyDomaintransferActionHandler_SuccessResponse_SuccessEPP() {
	expectedContext := context.Background()
	job := &model.Job{
		ID: "test-job-id",
		Info: &model.VJob{
			Data: sqlx.JSONText(`{"name": "test-domain.sexy"}`),
		},
	}

	response := &ryinterface.DomainTransferResponse{
		RegistryResponse: &common.RegistryResponse{
			IsSuccess: true,
			EppCode:   1000,
		},
	}

	service := NewWorkerService(suite.mb, suite.db, suite.t)
	suite.s.On("Context").Return(expectedContext)
	suite.s.On("Headers").Return(nil)
	suite.db.On("SetJobStatus", expectedContext, job, types.JobStatus.Completed, mock.Anything).Return(nil)

	err := service.RyDomainTransferActionHandler(suite.s, response, job, suite.db, log.GetLogger())
	suite.NoError(err)
	suite.db.AssertExpectations(suite.T())
}

func (suite *RyDomainTransferActionHandlerTestSuite) TestRyDomaintransferActionHandler_SuccessResponse_NonSuccessEPP() {
	expectedContext := context.Background()
	job := &model.Job{
		ID: "test-job-id",
		Info: &model.VJob{
			Data: sqlx.JSONText(`{"name": "test-domain.sexy"}`),
		},
	}

	response := &ryinterface.DomainTransferResponse{
		RegistryResponse: &common.RegistryResponse{
			IsSuccess: true,
			EppCode:   1001,
		},
	}
	service := NewWorkerService(suite.mb, suite.db, suite.t)
	suite.s.On("Context").Return(expectedContext)
	suite.s.On("Headers").Return(nil)
	suite.db.On("SetJobStatus", expectedContext, job, types.JobStatus.Failed, mock.Anything).Return(nil)

	err := service.RyDomainTransferActionHandler(suite.s, response, job, suite.db, log.GetLogger())
	suite.NoError(err)
	suite.db.AssertExpectations(suite.T())
}

func (suite *RyDomainTransferActionHandlerTestSuite) TestRyDomaintransferActionHandler_Failure() {
	expectedContext := context.Background()
	job := &model.Job{
		ID: "test-job-id",
		Info: &model.VJob{
			Data: sqlx.JSONText(`{"name": "test-domain.sexy"}`),
		},
	}

	response := &ryinterface.DomainTransferResponse{
		RegistryResponse: &common.RegistryResponse{
			IsSuccess:  false,
			EppCode:    2304,
			EppMessage: "Object status prohibits operation",
		},
	}

	service := NewWorkerService(suite.mb, suite.db, suite.t)
	suite.s.On("Headers").Return(nil)
	suite.s.On("Context").Return(expectedContext)
	suite.db.On("SetJobStatus", expectedContext, job, types.JobStatus.Failed, mock.Anything).Return(nil)

	err := service.RyDomainTransferActionHandler(suite.s, response, job, suite.db, log.GetLogger())
	suite.NoError(err)
	suite.db.AssertExpectations(suite.T())
}

func (suite *RyDomainTransferActionHandlerTestSuite) TestRyDomaintransferActionHandler_InvalidJSON() {
	expectedContext := context.Background()
	job := &model.Job{
		ID: "test-job-id",
		Info: &model.VJob{
			Data: sqlx.JSONText(`{"name": "test-domain.sexy",`), // Invalid JSON
		},
	}

	response := &ryinterface.DomainTransferResponse{
		RegistryResponse: &common.RegistryResponse{
			IsSuccess: true,
			EppCode:   1000,
		},
	}

	service := NewWorkerService(suite.mb, suite.db, suite.t)
	suite.s.On("Headers").Return(nil)
	suite.s.On("Context").Return(expectedContext)
	suite.db.On("SetJobStatus", expectedContext, job, types.JobStatus.Failed, mock.Anything).Return(nil)

	err := service.RyDomainTransferActionHandler(suite.s, response, job, suite.db, log.GetLogger())
	suite.NoError(err)
	suite.db.AssertExpectations(suite.T())
}

func (suite *RyDomainTransferActionHandlerTestSuite) TestRyDomaintransferActionHandler_FailureResponse_FailureEPP() {
	expectedContext := context.Background()
	job := &model.Job{
		ID: "test-job-id",
		Info: &model.VJob{
			Data: sqlx.JSONText(`{"name": "test-domain.sexy"}`),
		},
	}

	response := &ryinterface.DomainTransferResponse{
		RegistryResponse: &common.RegistryResponse{
			IsSuccess: true,
			EppCode:   1000,
		},
	}

	service := NewWorkerService(suite.mb, suite.db, suite.t)
	suite.s.On("Context").Return(expectedContext)
	suite.s.On("Headers").Return(nil)
	suite.db.On("SetJobStatus", expectedContext, job, types.JobStatus.Completed, mock.Anything).Return(nil)

	err := service.RyDomainTransferActionHandler(suite.s, response, job, suite.db, log.GetLogger())
	suite.NoError(err)
	suite.db.AssertExpectations(suite.T())
}
