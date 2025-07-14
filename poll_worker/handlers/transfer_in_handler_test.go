package handlers

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

type TransferInTestSuite struct {
	suite.Suite
	service *WorkerService
	db      *database.MockDatabase
	ctx     context.Context
}

func TestTransferInTestSuite(t *testing.T) {
	suite.Run(t, new(TransferInTestSuite))
}

func (suite *TransferInTestSuite) SetupSuite() {
	suite.db = &database.MockDatabase{}
	suite.service = &WorkerService{db: suite.db}
	suite.ctx = context.Background()

	config := config.Config{}
	config.LogLevel = "mute" // suppress log output

	log.Setup(config)
}

func (suite *TransferInTestSuite) TestHandlerTransferInRequest() {
	dbError := fmt.Errorf("database error")
	tests := []struct {
		name             string
		requestStatus    string
		TransferStatusID string
		mockSetup        func()
		expectedError    error
	}{
		{
			name:             "ClientRejected",
			requestStatus:    TransferStatus.ClientRejected,
			TransferStatusID: "test-transfer-status-id",
			mockSetup: func() {
				suite.db.On("GetProvisionDomainTransferInRequest", suite.ctx, mock.Anything).Return(&model.ProvisionDomainTransferInRequest{
					ID: "test-id",
				}, nil)
				suite.db.On("GetTransferStatusId", TransferStatus.ClientRejected).Return("test-transfer-status-id")
				suite.db.On("GetProvisionStatusId", mock.Anything).Return("test-status-id")
				suite.db.On("UpdateProvisionDomainTransferInRequest", suite.ctx, &model.ProvisionDomainTransferInRequest{
					ID:               "test-id",
					StatusID:         "test-status-id",
					TransferStatusID: "test-transfer-status-id",
				}).Return(nil)
			},
			expectedError: nil,
		},
		{
			name:             "PendingStatus",
			requestStatus:    TransferStatus.Pending,
			TransferStatusID: "test-transfer-status-id",
			mockSetup: func() {
				suite.db.On("GetProvisionStatusId", mock.Anything).Return("test-status-id")
				suite.db.On("GetProvisionDomainTransferInRequest", suite.ctx, mock.Anything).Return(&model.ProvisionDomainTransferInRequest{
					ID: "test-id",
				}, nil)
			},
			expectedError: nil,
		},
		{
			name:             "DatabaseError",
			requestStatus:    TransferStatus.ClientRejected,
			TransferStatusID: "test-transfer-status-id",
			mockSetup: func() {
				suite.db.On("GetProvisionStatusId", mock.Anything).Return("test-status-id")
				suite.db.On("GetProvisionDomainTransferInRequest", suite.ctx, mock.Anything).Return(&model.ProvisionDomainTransferInRequest{}, dbError)
			},
			expectedError: dbError,
		},
		{
			name:             "NotFound",
			requestStatus:    TransferStatus.ClientRejected,
			TransferStatusID: "test-transfer-status-id",
			mockSetup: func() {
				suite.db.On("GetProvisionStatusId", mock.Anything).Return("test-status-id")
				suite.db.On("GetProvisionDomainTransferInRequest", suite.ctx, mock.Anything).Return(&model.ProvisionDomainTransferInRequest{}, database.ErrNotFound)
			},
			expectedError: nil,
		},
		{
			name:             "InvalidTransferStatus",
			requestStatus:    "invalid-status",
			TransferStatusID: "",
			mockSetup: func() {
				suite.db.On("GetProvisionStatusId", mock.Anything).Return("test-status-id")
				suite.db.On("GetProvisionDomainTransferInRequest", suite.ctx, mock.Anything).Return(&model.ProvisionDomainTransferInRequest{
					ID: "test-id",
				}, nil)
				suite.db.On("GetTransferStatusId", "invalid-status").Return("")
			},
			expectedError: errors.New("invalid transfer status"),
		},
	}
	domainName := "test.com"

	for _, tt := range tests {
		suite.Run(tt.name, func() {
			request := &ryinterface.EppPollTrnData{
				Name:   &domainName,
				Status: &tt.requestStatus,
			}

			suite.db = &database.MockDatabase{}
			suite.service = &WorkerService{db: suite.db}
			tt.mockSetup()

			err := suite.service.handlerTransferInRequest(suite.ctx, request, &model.Accreditation{})
			if tt.expectedError != nil {
				suite.ErrorContains(err, tt.expectedError.Error())
			} else {
				suite.ErrorIs(err, nil)
			}
		})
	}
}
