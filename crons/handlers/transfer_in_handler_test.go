package handlers

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

const (
	domainName = "example.com"
)

func TestTransferInTestSuite(t *testing.T) {
	suite.Run(t, new(TransferInTestSuite))
}

type TransferInTestSuite struct {
	suite.Suite
	service *CronService
	cfg     config.Config
	db      database.Database
	mb      *mocks.MockMessageBus
	s       *mocks.MockMessageBusServer
}

func (s *TransferInTestSuite) SetupSuite() {
	cfg, err := config.LoadConfiguration("../../.env")
	s.NoError(err, "Failed to read config from .env")

	cfg.LogLevel = "mute" // suppress log output
	log.Setup(cfg)

	db, err := database.New(cfg.PostgresPoolConfig(), cfg.GetDBLogLevel())
	s.NoError(err, types.LogMessages.DatabaseConnectionFailed)
	s.db = db
	s.cfg = cfg
}

func (s *TransferInTestSuite) SetupTest() {
	s.mb = &mocks.MockMessageBus{}
	s.s = &mocks.MockMessageBusServer{}
	s.service = &CronService{cfg: s.cfg, db: s.db, bus: s.mb}
}

func getTenantCustomerId(db database.Database) (id string, err error) {
	tx := db.GetDB()
	err = tx.Table("tenant_customer").Select("id").Scan(&id).Error
	return
}

func getAccreditation(db database.Database) (acc *model.Accreditation, err error) {
	tx := db.GetDB()
	err = tx.Table("accreditation").Select("*").Scan(&acc).Error
	return
}

func getAccreditationTldId(db database.Database) (id string, err error) {
	tx := db.GetDB()
	err = tx.Table("accreditation_tld").Select("id").Scan(&id).Error
	return
}

func insertTransferInTestData(db database.Database) (pdti *model.ProvisionDomainTransferInRequest, accreditation *model.Accreditation, err error) {
	tx := db.GetDB()

	accreditation, err = getAccreditation(db)
	if err != nil {
		return
	}

	accreditationTldId, err := getAccreditationTldId(db)
	if err != nil {
		return
	}

	tenantCustomerId, err := getTenantCustomerId(db)
	if err != nil {
		return
	}

	actionDate := time.Now().Add(-10 * time.Hour)
	pdti = &model.ProvisionDomainTransferInRequest{
		DomainName:         domainName,
		AccreditationID:    accreditation.ID,
		AccreditationTldID: accreditationTldId,
		TenantCustomerID:   tenantCustomerId,
		ActionDate:         &actionDate,
		StatusID:           db.GetProvisionStatusId(types.ProvisionStatus.PendingAction),
		RequestedBy:        &accreditation.RegistrarID,
	}

	err = tx.Create(pdti).Error

	return
}

func (s *TransferInTestSuite) TestTransferInHandler_Accepted_Transferred() {
	pd, acc, err := insertTransferInTestData(s.db)
	s.NoError(err, "Failed to insert test transfer request")

	ctx := context.Background()

	// Mock message bus response for DomainTransferQueryRequest
	s.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainTransferQueryRequest"), mock.Anything).
		Return(messagebus.RpcResponse{
			Message: &ryinterface.DomainTransferResponse{
				Status:      types.TransferStatus.ClientApproved,
				Name:        domainName,
				RequestedBy: acc.RegistrarID,
				RegistryResponse: &common.RegistryResponse{
					EppCode: 1000,
				},
			},
		}, nil,
		)

	handler := s.service.ProcessPendingTransferInRequestMessage

	// Call the method
	err = handler(ctx)
	s.NoError(err, "Error processing pending transfer in request")

	var updatedRequest model.ProvisionDomainTransferInRequest
	err = s.db.GetDB().Where("id = ?", pd.ID).First(&updatedRequest).Error
	s.NoError(err, "Failed to fetch updated transfer request")
	s.Equal(types.ProvisionStatus.Completed, s.db.GetProvisionStatusName(updatedRequest.StatusID), "Transfer request status should be updated to completed")
	s.Equal(types.TransferStatus.ClientApproved, s.db.GetTransferStatusName(updatedRequest.TransferStatusID), "Transfer status should be updated to client approved")
}

func (s *TransferInTestSuite) TestTransferInHandler_Rejected_NotTransferred() {
	pd, acc, err := insertTransferInTestData(s.db)
	s.NoError(err, "Failed to insert test transfer request")

	ctx := context.Background()

	// Mock message bus response for DomainTransferQueryRequest
	s.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainTransferQueryRequest"), mock.Anything).
		Return(messagebus.RpcResponse{
			Message: &ryinterface.DomainTransferResponse{
				Status:      types.TransferStatus.ClientRejected,
				Name:        domainName,
				RequestedBy: acc.RegistrarID,
				RegistryResponse: &common.RegistryResponse{
					EppCode: 1000,
				},
			},
		},
			nil,
		)

	// Mock message bus response for DomainInfoRequest
	s.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainInfoRequest"), mock.Anything).
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

	handler := s.service.ProcessPendingTransferInRequestMessage

	// Call the method
	err = handler(ctx)
	s.NoError(err, "Error processing pending transfer in request")

	var updatedRequest model.ProvisionDomainTransferInRequest
	err = s.db.GetDB().Where("id = ?", pd.ID).First(&updatedRequest).Error
	s.NoError(err, "Failed to fetch updated transfer request")
	s.Equal(types.ProvisionStatus.Completed, s.db.GetProvisionStatusName(updatedRequest.StatusID), "Transfer request status should be updated to completed")
	s.Equal(types.TransferStatus.ClientRejected, s.db.GetTransferStatusName(updatedRequest.TransferStatusID), "Transfer status should be updated to client approved")
}

func (s *TransferInTestSuite) TestTransferInHandler_RejectedByDifferentClientId_NotTransferred() {
	pd, _, err := insertTransferInTestData(s.db)
	s.NoError(err, "Failed to insert test transfer request")

	ctx := context.Background()

	// Mock message bus response for DomainTransferQueryRequest
	s.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainTransferQueryRequest"), mock.Anything).
		Return(messagebus.RpcResponse{
			Message: &ryinterface.DomainTransferResponse{
				Status:      types.TransferStatus.ClientRejected,
				Name:        domainName,
				RequestedBy: "other-registrar",
				RegistryResponse: &common.RegistryResponse{
					EppCode: 1000,
				},
			},
		},
			nil,
		)

	// Mock message bus response for DomainInfoRequest
	s.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainInfoRequest"), mock.Anything).
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

	handler := s.service.ProcessPendingTransferInRequestMessage

	// Call the method
	err = handler(ctx)
	s.NoError(err, "Error processing pending transfer in request")

	var updatedRequest model.ProvisionDomainTransferInRequest
	err = s.db.GetDB().Where("id = ?", pd.ID).First(&updatedRequest).Error
	s.NoError(err, "Failed to fetch updated transfer request")
	s.Equal(types.ProvisionStatus.Completed, s.db.GetProvisionStatusName(updatedRequest.StatusID), "Transfer request status should be updated to completed")
	s.Equal(types.TransferStatus.ClientRejected, s.db.GetTransferStatusName(updatedRequest.TransferStatusID), "Transfer status should be updated to client approved")
}

func (s *TransferInTestSuite) TestTransferInHandler_RejectedByDifferentClientId_Transferred() {
	pd, acc, err := insertTransferInTestData(s.db)
	s.NoError(err, "Failed to insert test transfer request")

	ctx := context.Background()

	// Mock message bus response for DomainTransferQueryRequest
	s.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainTransferQueryRequest"), mock.Anything).
		Return(messagebus.RpcResponse{
			Message: &ryinterface.DomainTransferResponse{
				Status:      types.TransferStatus.ClientRejected,
				Name:        domainName,
				RequestedBy: "other-registrar",
				RegistryResponse: &common.RegistryResponse{
					EppCode: 1000,
				},
			},
		},
			nil,
		)

	// Mock message bus response for DomainInfoRequest
	s.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainInfoRequest"), mock.Anything).
		Return(messagebus.RpcResponse{
			Message: &ryinterface.DomainInfoResponse{
				Name: domainName,
				Clid: acc.RegistrarID,
				RegistryResponse: &common.RegistryResponse{
					EppCode: 1000,
				},
			},
		},
			nil,
		)

	handler := s.service.ProcessPendingTransferInRequestMessage

	// Call the method
	err = handler(ctx)
	s.NoError(err, "Error processing pending transfer in request")

	var updatedRequest model.ProvisionDomainTransferInRequest
	err = s.db.GetDB().Where("id = ?", pd.ID).First(&updatedRequest).Error
	s.NoError(err, "Failed to fetch updated transfer request")
	s.Equal(types.ProvisionStatus.Completed, s.db.GetProvisionStatusName(updatedRequest.StatusID), "Transfer request status should be updated to completed")
	s.Equal(types.TransferStatus.ClientApproved, s.db.GetTransferStatusName(updatedRequest.TransferStatusID), "Transfer status should be updated to client approved")
}

func (s *TransferInTestSuite) TestTransferInHandler_PendingBySameClientId() {
	pd, acc, err := insertTransferInTestData(s.db)
	s.NoError(err, "Failed to insert test transfer request")

	ctx := context.Background()

	// Mock message bus response for DomainTransferQueryRequest
	s.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainTransferQueryRequest"), mock.Anything).
		Return(messagebus.RpcResponse{
			Message: &ryinterface.DomainTransferResponse{
				Status:      types.TransferStatus.Pending,
				Name:        domainName,
				RequestedBy: acc.RegistrarID,
				RegistryResponse: &common.RegistryResponse{
					EppCode: 1000,
				},
			},
		},
			nil,
		)

	handler := s.service.ProcessPendingTransferInRequestMessage

	// Call the method
	err = handler(ctx)
	s.NoError(err, "Error processing pending transfer in request")

	var updatedRequest model.ProvisionDomainTransferInRequest
	err = s.db.GetDB().Where("id = ?", pd.ID).First(&updatedRequest).Error
	s.NoError(err, "Failed to fetch updated transfer request")
	s.Equal(types.ProvisionStatus.PendingAction, s.db.GetProvisionStatusName(updatedRequest.StatusID), "Transfer request status should be updated to completed")
	s.Equal(types.TransferStatus.Pending, s.db.GetTransferStatusName(updatedRequest.TransferStatusID), "Transfer status should be updated to client approved")
}

func (s *TransferInTestSuite) TestTransferInHandler_PendingByDifferentClientId_Transferred() {
	pd, acc, err := insertTransferInTestData(s.db)
	s.NoError(err, "Failed to insert test transfer request")

	ctx := context.Background()

	// Mock message bus response for DomainTransferQueryRequest
	s.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainTransferQueryRequest"), mock.Anything).
		Return(messagebus.RpcResponse{
			Message: &ryinterface.DomainTransferResponse{
				Status:      types.TransferStatus.Pending,
				Name:        domainName,
				RequestedBy: "other-registrar",
				RegistryResponse: &common.RegistryResponse{
					EppCode: 1000,
				},
			},
		},
			nil,
		)

	// Mock message bus response for DomainInfoRequest
	s.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainInfoRequest"), mock.Anything).
		Return(messagebus.RpcResponse{
			Message: &ryinterface.DomainInfoResponse{
				Name: domainName,
				Clid: acc.RegistrarID,
				RegistryResponse: &common.RegistryResponse{
					EppCode: 1000,
				},
			},
		},
			nil,
		)

	handler := s.service.ProcessPendingTransferInRequestMessage

	// Call the method
	err = handler(ctx)
	s.NoError(err, "Error processing pending transfer in request")

	var updatedRequest model.ProvisionDomainTransferInRequest
	err = s.db.GetDB().Where("id = ?", pd.ID).First(&updatedRequest).Error
	s.NoError(err, "Failed to fetch updated transfer request")
	s.Equal(types.ProvisionStatus.Completed, s.db.GetProvisionStatusName(updatedRequest.StatusID), "Transfer request status should be updated to completed")
	s.Equal(types.TransferStatus.ClientApproved, s.db.GetTransferStatusName(updatedRequest.TransferStatusID), "Transfer status should be updated to client approved")
}

func (s *TransferInTestSuite) TestTransferInHandler_PendingByDifferentClientId_NotTransferred() {
	pd, _, err := insertTransferInTestData(s.db)
	s.NoError(err, "Failed to insert test transfer request")

	ctx := context.Background()

	// Mock message bus response for DomainTransferQueryRequest
	s.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainTransferQueryRequest"), mock.Anything).
		Return(messagebus.RpcResponse{
			Message: &ryinterface.DomainTransferResponse{
				Status:      types.TransferStatus.Pending,
				Name:        domainName,
				RequestedBy: "other-registrar",
				RegistryResponse: &common.RegistryResponse{
					EppCode: 1000,
				},
			},
		},
			nil,
		)

	// Mock message bus response for DomainInfoRequest
	s.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainInfoRequest"), mock.Anything).
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

	handler := s.service.ProcessPendingTransferInRequestMessage

	// Call the method
	err = handler(ctx)
	s.NoError(err, "Error processing pending transfer in request")

	var updatedRequest model.ProvisionDomainTransferInRequest
	err = s.db.GetDB().Where("id = ?", pd.ID).First(&updatedRequest).Error
	s.NoError(err, "Failed to fetch updated transfer request")
	s.Equal(types.ProvisionStatus.Completed, s.db.GetProvisionStatusName(updatedRequest.StatusID), "Transfer request status should be updated to completed")
	s.Equal(types.TransferStatus.ClientRejected, s.db.GetTransferStatusName(updatedRequest.TransferStatusID), "Transfer status should be updated to client approved")
}

func (s *TransferInTestSuite) TestTransferInHandler_NoPendingTransfer_Transferred() {
	pd, acc, err := insertTransferInTestData(s.db)
	s.NoError(err, "Failed to insert test transfer request")

	ctx := context.Background()

	// Mock message bus response for DomainTransferQueryRequest
	s.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainTransferQueryRequest"), mock.Anything).
		Return(messagebus.RpcResponse{
			Message: &ryinterface.DomainTransferResponse{
				RegistryResponse: &common.RegistryResponse{
					EppCode: 2301,
				},
			},
		},
			nil,
		)

	// Mock message bus response for DomainInfoRequest
	s.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainInfoRequest"), mock.Anything).
		Return(messagebus.RpcResponse{
			Message: &ryinterface.DomainInfoResponse{
				Name: domainName,
				Clid: acc.RegistrarID,
				RegistryResponse: &common.RegistryResponse{
					EppCode: 1000,
				},
			},
		},
			nil,
		)

	handler := s.service.ProcessPendingTransferInRequestMessage

	// Call the method
	err = handler(ctx)
	s.NoError(err, "Error processing pending transfer in request")

	var updatedRequest model.ProvisionDomainTransferInRequest
	err = s.db.GetDB().Where("id = ?", pd.ID).First(&updatedRequest).Error
	s.NoError(err, "Failed to fetch updated transfer request")
	s.Equal(types.ProvisionStatus.Completed, s.db.GetProvisionStatusName(updatedRequest.StatusID), "Transfer request status should be updated to completed")
	s.Equal(types.TransferStatus.ClientApproved, s.db.GetTransferStatusName(updatedRequest.TransferStatusID), "Transfer status should be updated to client approved")
}

func (s *TransferInTestSuite) TestTransferInHandler_NoPendingTransfer_NotTransferred() {
	pd, _, err := insertTransferInTestData(s.db)
	s.NoError(err, "Failed to insert test transfer request")

	ctx := context.Background()

	// Mock message bus response for DomainTransferQueryRequest
	s.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainTransferQueryRequest"), mock.Anything).
		Return(messagebus.RpcResponse{
			Message: &ryinterface.DomainTransferResponse{
				RegistryResponse: &common.RegistryResponse{
					EppCode: 2301,
				},
			},
		},
			nil,
		)

	// Mock message bus response for DomainInfoRequest
	s.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainInfoRequest"), mock.Anything).
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

	handler := s.service.ProcessPendingTransferInRequestMessage

	// Call the method
	err = handler(ctx)
	s.NoError(err, "Error processing pending transfer in request")

	var updatedRequest model.ProvisionDomainTransferInRequest
	err = s.db.GetDB().Where("id = ?", pd.ID).First(&updatedRequest).Error
	s.NoError(err, "Failed to fetch updated transfer request")
	s.Equal(types.ProvisionStatus.Completed, s.db.GetProvisionStatusName(updatedRequest.StatusID), "Transfer request status should be updated to completed")
	s.Equal(types.TransferStatus.ClientRejected, s.db.GetTransferStatusName(updatedRequest.TransferStatusID), "Transfer status should be updated to client approved")
}
