package handlers

import (
	"context"
	"fmt"
	"testing"

	"github.com/google/uuid"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

type TransferAwayCronTestSuite struct {
	suite.Suite
	service *CronService
	cfg     config.Config
	db      *database.MockDatabase
	bus     *mocks.MockMessageBus
	ctx     context.Context
}

func TestTransferAwayCronTestSuite(t *testing.T) {
	suite.Run(t, new(TransferAwayCronTestSuite))
}

func (suite *TransferAwayCronTestSuite) SetupSuite() {
	suite.cfg = config.Config{}
	suite.db = &database.MockDatabase{}
	suite.bus = &mocks.MockMessageBus{}
	suite.service = &CronService{cfg: suite.cfg, db: suite.db, bus: suite.bus}
	suite.ctx = context.Background()
	log.Setup(suite.cfg)
}

func (suite *TransferAwayCronTestSuite) TestProcessTransferAwayOrders() {
	dbError := fmt.Errorf("database error")
	tests := []struct {
		name          string
		mockSetup     func()
		expectedError error
	}{
		{
			name: "test non-owned domain info response",
			mockSetup: func() {
				suite.bus.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainInfoRequest"), mock.Anything).
					Return(messagebus.RpcResponse{
						Message: &ryinterface.DomainInfoResponse{
							Name: domainName,
							Clid: "other-registrar",
							RegistryResponse: &common.RegistryResponse{
								EppCode: 1000,
							},
						},
					},
						nil,
					)

				suite.db.On("GetActionableTransferAwayOrders", suite.ctx, DefaultTransferAwayOrdersBatchSize).Return([]model.VOrderTransferAwayDomain{
					{OrderID: "order1", AccreditationID: "acc1", DomainName: "test.com", TransferStatus: types.TransferStatus.Pending},
				}, nil)
				suite.db.On("GetTransferStatusId", types.TransferStatus.ServerApproved).Return("test-transfer-status-id")
				suite.db.On("GetAccreditationById", suite.ctx, "acc1").Return(&model.Accreditation{RegistrarID: "reg1"}, nil)
				suite.db.On("GetDomainInfo", suite.ctx, "test.com", mock.Anything).Return(&ryinterface.DomainInfoResponse{Clid: "reg1"}, nil)
				suite.db.On("OrderNextStatus", suite.ctx, "order1", true).Return(nil)
				suite.db.On("UpdateTransferAwayDomain", suite.ctx, &model.OrderItemTransferAwayDomain{
					ID:               types.ToPointer(""),
					OrderID:          "",
					TransferStatusID: "test-transfer-status-id",
				}).Return(nil)
			},
			expectedError: nil,
		},
		{
			name: "DatabaseError",
			mockSetup: func() {
				suite.db.On("GetActionableTransferAwayOrders", suite.ctx, DefaultTransferAwayOrdersBatchSize).Return([]model.VOrderTransferAwayDomain{}, dbError)
			},
			expectedError: dbError,
		},
		{
			name: "error getting accreditation by id",
			mockSetup: func() {
				suite.db.On("GetActionableTransferAwayOrders", suite.ctx, DefaultTransferAwayOrdersBatchSize).Return([]model.VOrderTransferAwayDomain{
					{OrderID: "order1", AccreditationID: "acc1", DomainName: "test.com", TransferStatus: types.TransferStatus.Pending},
				}, nil)
				suite.db.On("GetAccreditationById", suite.ctx, "acc1").Return(&model.Accreditation{}, dbError)
			},
			expectedError: nil,
		},
	}

	for _, tt := range tests {
		suite.Run(tt.name, func() {
			suite.SetupSuite()
			tt.mockSetup()
			err := suite.service.ProcessTransferAwayOrders(suite.ctx)
			if tt.expectedError != nil {
				suite.ErrorContains(err, tt.expectedError.Error())
			} else {
				suite.ErrorIs(err, nil)
			}
		})
	}
}

func (suite *TransferAwayCronTestSuite) TestProcessTransferAwayOrder() {
	messagebusError := fmt.Errorf("messagebus error")
	tests := []struct {
		name                string
		mockSetup           func()
		OrderTransferStatus string
		expectedError       error
	}{
		{
			name:                "domain is auto transfer approved",
			OrderTransferStatus: types.TransferStatus.Pending,
			mockSetup: func() {
				suite.db.On("GetAccreditationById", suite.ctx, "acc1").Return(&model.Accreditation{RegistrarID: "reg1"}, nil)
				suite.bus.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainInfoRequest"), mock.Anything).
					Return(messagebus.RpcResponse{
						Message: &ryinterface.DomainInfoResponse{
							Name: domainName,
							Clid: "reg1",
							RegistryResponse: &common.RegistryResponse{
								EppCode: 1000,
							},
						},
					},
						nil,
					)
				suite.db.On("GetTLDSetting", suite.ctx, "tld1", "tld.lifecycle.transfer_server_auto_approve_supported").Return(&model.VAttribute{Value: "true"}, nil)
			},
			expectedError: nil,
		},
		{
			name:                "error getting domain info",
			OrderTransferStatus: types.TransferStatus.Pending,
			mockSetup: func() {
				suite.db.On("GetAccreditationById", suite.ctx, "acc1").Return(&model.Accreditation{RegistrarID: "reg1"}, nil)
				suite.bus.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainInfoRequest"), mock.Anything).
					Return(messagebus.RpcResponse{}, messagebusError)
			},
			expectedError: messagebusError,
		},
	}

	for _, tt := range tests {
		suite.Run(tt.name, func() {
			order := model.VOrderTransferAwayDomain{
				OrderID:            "order1",
				AccreditationID:    "acc1",
				DomainName:         "test.com",
				TransferStatus:     tt.OrderTransferStatus,
				AccreditationTldID: "tld1",
			}

			suite.SetupSuite()
			tt.mockSetup()
			logger := log.CreateChildLogger(log.Fields{
				types.LogFieldKeys.LogID:    uuid.NewString(),
				types.LogFieldKeys.CronType: "ProcessTransferAwayOrders",
				types.LogFieldKeys.Domain:   domainName,
			})
			err := suite.service.processTransferAwayOrder(suite.ctx, order, logger)
			if tt.expectedError != nil {
				suite.ErrorContains(err, tt.expectedError.Error())
			} else {
				suite.ErrorIs(err, nil)
			}
		})
	}
}

func (suite *TransferAwayCronTestSuite) TestHandlePendingTransfer() {
	dbError := fmt.Errorf("database error")
	tests := []struct {
		name          string
		mockSetup     func()
		expectedError error
	}{
		{
			name: "server is auto approved",
			mockSetup: func() {
				suite.db.On("GetTLDSetting", suite.ctx, "tld1", "tld.lifecycle.transfer_server_auto_approve_supported").Return(&model.VAttribute{Value: "true"}, nil)
			},
			expectedError: nil,
		},
		{
			name: "failed to get TLD setting",
			mockSetup: func() {
				suite.db.On("GetTLDSetting", suite.ctx, "tld1", "tld.lifecycle.transfer_server_auto_approve_supported").Return(&model.VAttribute{}, dbError)
			},
			expectedError: dbError,
		},
		{
			name: "unexpected value for auto transfer approval",
			mockSetup: func() {
				suite.db.On("GetTLDSetting", suite.ctx, "tld1", "tld.lifecycle.transfer_server_auto_approve_supported").Return(&model.VAttribute{Value: "test"}, nil)
			},
			expectedError: fmt.Errorf("failed to parse auto-transfer approval setting: strconv.ParseBool"),
		},
		{
			name: "client approve transfer",
			mockSetup: func() {
				suite.db.On("GetTLDSetting", suite.ctx, "tld1", "tld.lifecycle.transfer_server_auto_approve_supported").Return(&model.VAttribute{Value: "false"}, nil)
				suite.db.On("GetTransferStatusId", types.TransferStatus.ClientApproved).Return("test-transfer-status-id")
				suite.db.On("UpdateTransferAwayDomain", suite.ctx, &model.OrderItemTransferAwayDomain{
					ID:               types.ToPointer("orderItem1"),
					TransferStatusID: "test-transfer-status-id",
				}).Return(nil)
				suite.db.On("OrderNextStatus", suite.ctx, "order1", true).Return(nil)
			},
			expectedError: nil,
		},
	}

	for _, tt := range tests {
		suite.Run(tt.name, func() {
			order := model.VOrderTransferAwayDomain{OrderID: "order1", OrderItemID: "orderItem1", AccreditationTldID: "tld1", TransferStatus: types.TransferStatus.Pending}
			suite.SetupSuite()
			tt.mockSetup()
			logger := log.CreateChildLogger(log.Fields{
				types.LogFieldKeys.LogID:   uuid.NewString(),
				types.LogFieldKeys.JobType: "ProcessTransferAwayOrders",
				types.LogFieldKeys.Domain:  domainName,
			})
			err := suite.service.handlePendingTransfer(suite.ctx, order, logger)
			if tt.expectedError != nil {
				suite.ErrorContains(err, tt.expectedError.Error())
			} else {
				suite.ErrorIs(err, nil)
			}
		})
	}
}
