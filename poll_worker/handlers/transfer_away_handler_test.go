package handlers

import (
	"context"
	"fmt"
	"testing"

	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
)

type TransferAwayTestSuite struct {
	suite.Suite
	service *WorkerService
	db      *database.MockDatabase
	ctx     context.Context
}

func TestTransferAwayTestSuite(t *testing.T) {
	suite.Run(t, new(TransferAwayTestSuite))
}

func (suite *TransferAwayTestSuite) SetupSuite() {
	suite.db = &database.MockDatabase{}
	suite.service = &WorkerService{db: suite.db}
	suite.ctx = context.Background()
	log.Setup(config.Config{})
}

func (suite *TransferAwayTestSuite) TestHandlerTransferAwayRequest() {
	dbError := fmt.Errorf("database error")
	testId := "test-id"
	tests := []struct {
		name          string
		requestStatus string
		mockSetup     func()
		expectedError error
	}{
		{
			name:          "PendingStatus",
			requestStatus: TransferStatus.Pending,
			mockSetup: func() {
				suite.db.On("GetDomainAccreditation", suite.ctx, mock.Anything).Return(&model.DomainWithAccreditation{
					Domain: model.Domain{
						Name: "test.com",
					},
					Accreditation: model.Accreditation{},
				}, nil)
				suite.db.On("GetOrderTypeId", "transfer_away", "domain").Return("test-order-type-id")
				suite.db.On("GetTransferStatusId", TransferStatus.Pending).Return("test-transfer-status-id")
				suite.db.On("TransferAwayDomainOrder", suite.ctx, mock.Anything).Return(nil)
			},
			expectedError: nil,
		},
		{
			name:          "ServerApprovedStatus",
			requestStatus: TransferStatus.ServerApproved,
			mockSetup: func() {
				suite.db.On("GetTransferAwayOrder", suite.ctx, types.OrderStatusEnum.Created, "test.com", mock.Anything).Return(&model.OrderItemTransferAwayDomain{
					ID:      &testId,
					OrderID: "test-order-id",
				}, nil)
				suite.db.On("GetTransferStatusId", TransferStatus.ServerApproved).Return("test-transfer-status-id")
				suite.db.On("UpdateTransferAwayDomain", suite.ctx, &model.OrderItemTransferAwayDomain{
					ID:               &testId,
					TransferStatusID: "test-transfer-status-id",
				}).Return(nil)
				suite.db.On("OrderNextStatus", suite.ctx, "test-order-id", true).Return(nil)
			},
			expectedError: nil,
		},
		{
			name:          "DatabaseError",
			requestStatus: TransferStatus.Pending,
			mockSetup: func() {
				suite.db.On("GetDomainAccreditation", suite.ctx, mock.Anything).Return(&model.DomainWithAccreditation{}, dbError)
			},
			expectedError: dbError,
		},
		{
			name:          "NotFound",
			requestStatus: TransferStatus.ServerApproved,
			mockSetup: func() {
				suite.db.On("GetTransferAwayOrder", suite.ctx, types.OrderStatusEnum.Created, "test.com", mock.Anything).Return(&model.OrderItemTransferAwayDomain{}, database.ErrNotFound)
				suite.db.On("GetDomainAccreditation", suite.ctx, mock.Anything).Return(&model.DomainWithAccreditation{}, database.ErrNotFound)
				suite.db.On("GetOrderTypeId", "transfer_away", "domain").Return("test-order-type-id")
				suite.db.On("GetTransferStatusId", TransferStatus.ServerApproved).Return("test-transfer-status-id")
				suite.db.On("TransferAwayDomainOrder", suite.ctx, mock.Anything).Return(nil)
				suite.db.On("GetTransferStatusName", TransferStatus.ServerApproved).Return("test-transfer-status-id")
				suite.db.On("UpdateTransferAwayDomain", suite.ctx, &model.OrderItemTransferAwayDomain{
					ID:               new(string),
					OrderID:          "",
					TransferStatusID: "test-transfer-status-id",
				}).Return(nil)
				suite.db.On("OrderNextStatus", suite.ctx, "", true).Return(nil)
			},
			expectedError: database.ErrNotFound,
		},
		{
			name:          "InvalidTransferStatus",
			requestStatus: "invalid-status",
			mockSetup:     func() {},
			expectedError: nil,
		},
		{
			name:          "DomainNotOwnedByRegistrar",
			requestStatus: TransferStatus.Pending,
			mockSetup: func() {
				suite.db.On("GetDomainAccreditation", suite.ctx, mock.Anything).Return(&model.DomainWithAccreditation{
					Domain: model.Domain{
						Name: "test.com",
					},
					Accreditation: model.Accreditation{ID: "different-id"},
				}, nil)
			},
			expectedError: fmt.Errorf("domain[test.com] is not owned by the registrar"),
		},
		{
			name:          "ErrorCreatingTransferAwayDomainOrder",
			requestStatus: TransferStatus.Pending,
			mockSetup: func() {
				suite.db.On("GetDomainAccreditation", suite.ctx, mock.Anything).Return(&model.DomainWithAccreditation{
					Domain: model.Domain{
						Name: "test.com",
					},
					Accreditation: model.Accreditation{},
				}, nil)
				suite.db.On("GetOrderTypeId", "transfer_away", "domain").Return("test-order-type-id")
				suite.db.On("GetTransferStatusId", TransferStatus.Pending).Return("test-transfer-status-id")
				suite.db.On("TransferAwayDomainOrder", suite.ctx, mock.Anything).Return(dbError)
			},
			expectedError: fmt.Errorf("error creating transfer away domain order: %w", dbError),
		},
		{
			name:          "ErrorUpdatingTransferAwayOrder",
			requestStatus: TransferStatus.ServerApproved,
			mockSetup: func() {
				suite.db.On("GetTransferAwayOrder", suite.ctx, types.OrderStatusEnum.Created, "test.com", mock.Anything).Return(&model.OrderItemTransferAwayDomain{
					ID:      &testId,
					OrderID: "test-order-id",
				}, nil)
				suite.db.On("GetTransferStatusId", TransferStatus.ServerApproved).Return("test-transfer-status-id")
				suite.db.On("UpdateTransferAwayDomain", suite.ctx, &model.OrderItemTransferAwayDomain{
					ID:               &testId,
					TransferStatusID: "test-transfer-status-id",
				}).Return(dbError)
			},
			expectedError: fmt.Errorf("error updating transfer away order for domain[test.com] with ServerApproved status: %w", dbError),
		},
		{
			name:          "FailedToUpdateOrderStatus",
			requestStatus: TransferStatus.ServerApproved,
			mockSetup: func() {
				suite.db.On("GetTransferAwayOrder", suite.ctx, types.OrderStatusEnum.Created, "test.com", mock.Anything).Return(&model.OrderItemTransferAwayDomain{
					ID:      &testId,
					OrderID: "test-order-id",
				}, nil)
				suite.db.On("GetTransferStatusId", TransferStatus.ServerApproved).Return("test-transfer-status-id")
				suite.db.On("UpdateTransferAwayDomain", suite.ctx, &model.OrderItemTransferAwayDomain{
					ID:               &testId,
					TransferStatusID: "test-transfer-status-id",
				}).Return(nil)
				suite.db.On("OrderNextStatus", suite.ctx, "test-order-id", true).Return(dbError)
			},
			expectedError: fmt.Errorf("failed to update order status: %w", dbError),
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

			err := suite.service.handlerTransferAwayRequest(suite.ctx, request, &model.Accreditation{})
			if tt.expectedError != nil {
				suite.ErrorContains(err, tt.expectedError.Error())
			} else {
				suite.ErrorIs(err, nil)
			}
		})
	}
}
