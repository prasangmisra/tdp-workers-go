package handlers

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	rymessages "github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	config "github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

func TestDomainTransferActionSuite(t *testing.T) {
	suite.Run(t, new(DomainTransferActionSuite))
}

type DomainTransferActionSuite struct {
	suite.Suite
	db     *database.MockDatabase
	mb     *mocks.MockMessageBus
	s      *mocks.MockMessageBusServer
	tracer *oteltrace.Tracer

	srv *WorkerService
}

func (suite *DomainTransferActionSuite) SetupTest() {
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
	suite.tracer = tracer

	suite.srv = NewWorkerService(suite.mb, suite.db, suite.tracer)
}

func (suite *DomainTransferActionSuite) TestDomainTransferActionHandler() {
	domainName := "test-domain.sexy"

	expectedJobStatusName := "submitted"
	expectedJob := &model.Job{
		ID: "test-job-id",
		Info: &model.VJob{
			JobStatusName: &expectedJobStatusName,
			JobTypeName:   types.ToPointer("provision_domain_transfer_away"),
		},
		StatusID: "submitted",
	}

	testCases := []struct {
		name           string
		transferStatus string
		expectedMsg    proto.Message
	}{
		{
			name:           "ClientApproved",
			transferStatus: types.TransferStatus.ClientApproved,
			expectedMsg: &rymessages.DomainTransferApproveRequest{
				Name: domainName,
			},
		},
		{
			name:           "ClientRejected",
			transferStatus: types.TransferStatus.ClientRejected,
			expectedMsg: &rymessages.DomainTransferRejectRequest{
				Name: domainName,
			},
		},
		{
			name:           "ClientCancelled",
			transferStatus: types.TransferStatus.ClientCancelled,
			expectedMsg: &rymessages.DomainTransferCancelRequest{
				Name: domainName,
			},
		},
	}

	for _, tc := range testCases {
		suite.Run(tc.name, func() {
			// Reset mock expectations for each test case
			suite.SetupTest()

			data := types.DomainTransferActionData{
				Name:           domainName,
				TransferStatus: tc.transferStatus,
				Accreditation: types.Accreditation{
					AccreditationName: "test-accreditation",
				},
			}
			serializedData, err := json.Marshal(data)
			suite.NoError(err, "Failed to serialize data")
			expectedJob.Info.Data = serializedData

			suite.db.On("WithTransaction", mock.Anything).Return(nil).Run(func(args mock.Arguments) {
				transactionFunc := args.Get(0).(func(database.Database) error)
				_ = transactionFunc(suite.db)
			})
			suite.db.On("GetJobById", mock.Anything, mock.Anything, mock.Anything).Return(expectedJob, nil)
			suite.db.On("GetJobStatusId", "submitted").Return("submitted")
			suite.db.On("SetJobStatus", mock.Anything, mock.Anything, "processing", mock.Anything).Return(nil)

			suite.s.On("Context").Return(context.Background())
			suite.s.On("MessageBus").Return(suite.mb)
			suite.mb.On("Send", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil)
			suite.s.On("Headers").Return(nil)

			msg := &job.Notification{
				JobId: "test-job-id",
			}

			handler := suite.srv.DomainTransferActionHandler
			err = handler(suite.s, msg)
			suite.NoError(err, types.LogMessages.HandleMessageFailed)

			suite.True(suite.s.AssertExpectations(suite.T()))
			suite.True(suite.mb.AssertExpectations(suite.T()))
			suite.True(suite.db.AssertExpectations(suite.T()))
		})
	}
}
