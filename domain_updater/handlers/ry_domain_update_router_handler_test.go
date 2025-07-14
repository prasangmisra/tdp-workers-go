package handlers

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message"
	commonmessages "github.com/tucowsinc/tdp-messages-go/message/common"
	rymessages "github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

func TestRyDomainUpdateRouterTestSuite(t *testing.T) {
	suite.Run(t, new(RyDomainUpdateRouterTestSuite))
}

type RyDomainUpdateRouterTestSuite struct {
	suite.Suite
	db database.Database
	mb *mocks.MockMessageBus
	s  *mocks.MockMessageBusServer
	t  *oteltrace.Tracer
}

func (suite *RyDomainUpdateRouterTestSuite) SetupSuite() {
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

	db, err := database.New(cfg.PostgresPoolConfig(), cfg.GetDBLogLevel())
	suite.NoError(err, types.LogMessages.DatabaseConnectionFailed)
	suite.db = db
}

func (suite *RyDomainUpdateRouterTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func (suite *RyDomainUpdateRouterTestSuite) TestRyDomainUpdateRouterTestSuite_UpdateHandler() {
	expectedContext := context.Background()

	job, err := insertRyDomainUpdateTestJob(suite.db)
	suite.NoError(err, "Failed to insert test job")

	envelope := &message.TcWire{CorrelationId: job.ID}

	err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to update test job")

	suite.s.On("Context").Return(expectedContext)
	suite.s.On("Headers").Return(nil)
	suite.s.On("Envelope").Return(envelope)

	msg := &rymessages.DomainUpdateResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  true,
			EppCode:    1000,
			EppMessage: "",
		},
	}

	service := NewWorkerService(suite.mb, suite.db, suite.t)

	handler := service.RyDomainUpdateRouter
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.s.AssertExpectations(suite.T())
}

func (suite *RyDomainUpdateRouterTestSuite) TestRyDomainUpdateRouterTestSuite_RedeemHandler() {
	expectedContext := context.Background()
	id := uuid.New().String()

	job, _, err := insertRyDomainRedeemTestJob(suite.db, id)
	suite.NoError(err, "Failed to insert test job")

	envelope := &message.TcWire{CorrelationId: job.ID}

	err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to update test job")

	domainInfoRequest := &rymessages.DomainInfoRequest{
		Name: "test-domain.sexy",
	}

	domainInfoResponse := &rymessages.DomainInfoResponse{
		Name:       "test-domain.sexy",
		ExpiryDate: timestamppb.New(time.Now().AddDate(1, 0, 0)),
	}

	suite.s.On("Context").Return(expectedContext)
	suite.s.On("Headers").Return(nil)
	suite.s.On("Envelope").Return(envelope)

	suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), types.GetTransformQueue("test-accreditationName"), domainInfoRequest, mock.Anything).Return(
		messagebus.RpcResponse{
			Server:  suite.s,
			Message: domainInfoResponse,
			Err:     nil,
		},
		nil,
	)

	msg := &rymessages.DomainUpdateResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  true,
			EppCode:    1000,
			EppMessage: "",
		},
		Extensions: map[string]*anypb.Any{},
	}

	service := NewWorkerService(suite.mb, suite.db, suite.t)

	handler := service.RyDomainUpdateRouter
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.s.AssertExpectations(suite.T())
}
