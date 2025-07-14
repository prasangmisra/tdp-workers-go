package handlers

import (
	"context"
	"fmt"
	"testing"
	"time"

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

type DomainPurgeCronTestSuite struct {
	suite.Suite
	service *CronService
	cfg     config.Config
	db      *database.MockDatabase
	bus     *mocks.MockMessageBus
	ctx     context.Context
}

func parseTimePointer(dateStr string) *time.Time {
	t, _ := time.Parse("2006-01-02", dateStr)
	return &t
}

func TestDomainPurgeCronTestSuite(t *testing.T) {
	suite.Run(t, new(DomainPurgeCronTestSuite))
}

func (suite *DomainPurgeCronTestSuite) SetupSuite() {
	suite.cfg = config.Config{}
	suite.db = &database.MockDatabase{}
	suite.bus = &mocks.MockMessageBus{}
	suite.service = &CronService{cfg: suite.cfg, db: suite.db, bus: suite.bus}
	suite.ctx = context.Background()
	log.Setup(suite.cfg)
}

func (suite *DomainPurgeCronTestSuite) TestProcessDomainsPurge() {
	domainName := "test.help"
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

				suite.db.On("GetPurgeableDomains", suite.ctx, DefaultPurgeableDomainsBatchSize).Return([]model.VDomain{
					{ID: types.ToPointer("domain1"), Name: &domainName, RgpEppStatus: nil, DeletedDate: parseTimePointer("2021-01-01")},
				}, nil)
				suite.db.On("GetDomainAccreditation", suite.ctx, domainName).Return(&model.DomainWithAccreditation{Accreditation: model.Accreditation{RegistrarID: "reg1"}}, nil)
				suite.db.On("GetDomainInfo", suite.ctx, "test.com", mock.Anything).Return(&ryinterface.DomainInfoResponse{Clid: "reg1"}, nil)
				suite.db.On("DeleteDomainWithReason", suite.ctx, "domain1", "deleted").Return(nil)
			},
			expectedError: nil,
		},
		{
			name: "test err code 2303 domain info response",
			mockSetup: func() {
				suite.bus.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainInfoRequest"), mock.Anything).
					Return(messagebus.RpcResponse{
						Message: &ryinterface.DomainInfoResponse{
							Name: domainName,
							Clid: "registrar",
							RegistryResponse: &common.RegistryResponse{
								EppCode: 2303,
							},
						},
					},
						nil,
					)

				suite.db.On("GetPurgeableDomains", suite.ctx, DefaultPurgeableDomainsBatchSize).Return([]model.VDomain{
					{ID: types.ToPointer("domain1"), Name: &domainName, RgpEppStatus: nil, DeletedDate: parseTimePointer("2021-01-01")},
				}, nil)
				suite.db.On("GetDomainAccreditation", suite.ctx, domainName).Return(&model.DomainWithAccreditation{Accreditation: model.Accreditation{RegistrarID: "reg1"}}, nil)
				suite.db.On("DeleteDomainWithReason", suite.ctx, "domain1", "deleted").Return(nil)
			},
			expectedError: nil,
		},
		{
			name: "test does not exist domain info response",
			mockSetup: func() {
				suite.bus.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainInfoRequest"), mock.Anything).
					Return(messagebus.RpcResponse{
						Message: &ryinterface.DomainInfoResponse{
							Name: domainName,
							Clid: "registrar",
							RegistryResponse: &common.RegistryResponse{
								EppCode:    2400,
								EppMessage: "Object does not exist",
							},
						},
					},
						nil,
					)

				suite.db.On("GetPurgeableDomains", suite.ctx, DefaultPurgeableDomainsBatchSize).Return([]model.VDomain{
					{ID: types.ToPointer("domain1"), Name: &domainName, RgpEppStatus: nil, DeletedDate: parseTimePointer("2021-01-01")},
				}, nil)
				suite.db.On("GetDomainAccreditation", suite.ctx, domainName).Return(&model.DomainWithAccreditation{Accreditation: model.Accreditation{RegistrarID: "reg1"}}, nil)
				suite.db.On("DeleteDomainWithReason", suite.ctx, "domain1", "deleted").Return(nil)
			},
			expectedError: nil,
		},
		{
			name: "test not found domain info response",
			mockSetup: func() {
				suite.bus.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainInfoRequest"), mock.Anything).
					Return(messagebus.RpcResponse{
						Message: &ryinterface.DomainInfoResponse{
							Name: domainName,
							Clid: "registrar",
							RegistryResponse: &common.RegistryResponse{
								EppCode:    2400,
								EppMessage: "domain object not found using search term",
							},
						},
					},
						nil,
					)

				suite.db.On("GetPurgeableDomains", suite.ctx, DefaultPurgeableDomainsBatchSize).Return([]model.VDomain{
					{ID: types.ToPointer("domain1"), Name: &domainName, RgpEppStatus: nil, DeletedDate: parseTimePointer("2021-01-01")},
				}, nil)
				suite.db.On("GetDomainAccreditation", suite.ctx, domainName).Return(&model.DomainWithAccreditation{Accreditation: model.Accreditation{RegistrarID: "reg1"}}, nil)
				suite.db.On("DeleteDomainWithReason", suite.ctx, "domain1", "deleted").Return(nil)
			},
			expectedError: nil,
		},
		{
			name: "DatabaseError",
			mockSetup: func() {
				suite.db.On("GetPurgeableDomains", suite.ctx, DefaultPurgeableDomainsBatchSize).Return([]model.VDomain{}, dbError)
			},
			expectedError: dbError,
		},
		{
			name: "error getting domain accreditation by domain name",
			mockSetup: func() {
				suite.db.On("GetPurgeableDomains", suite.ctx, DefaultPurgeableDomainsBatchSize).Return([]model.VDomain{
					{ID: types.ToPointer("domain1"), Name: &domainName, RgpEppStatus: nil, DeletedDate: parseTimePointer("2021-01-01")},
				}, nil)
				suite.db.On("GetDomainAccreditation", suite.ctx, domainName).Return(&model.DomainWithAccreditation{}, dbError)
			},
			expectedError: nil,
		},
	}

	for _, tt := range tests {
		suite.Run(tt.name, func() {
			suite.SetupSuite()
			tt.mockSetup()
			err := suite.service.ProcessDomainsPurge(suite.ctx)
			if tt.expectedError != nil {
				suite.ErrorContains(err, tt.expectedError.Error())
			} else {
				suite.ErrorIs(err, nil)
			}
		})
	}
}

func (suite *DomainPurgeCronTestSuite) TestProcessDomainPurgeOrder() {
	domainName := "test.help"
	messagebusError := fmt.Errorf("messagebus error")

	tests := []struct {
		name                string
		mockSetup           func()
		OrderTransferStatus string
		expectedError       error
	}{
		{
			name:                "error getting domain info",
			OrderTransferStatus: types.TransferStatus.Pending,
			mockSetup: func() {
				suite.db.On("GetDomainAccreditation", suite.ctx, domainName).Return(&model.DomainWithAccreditation{Accreditation: model.Accreditation{RegistrarID: "reg1"}}, nil)
				suite.bus.On("Call", mock.AnythingOfType("*context.timerCtx"), mock.Anything, mock.AnythingOfType("*ryinterface.DomainInfoRequest"), mock.Anything).
					Return(messagebus.RpcResponse{}, messagebusError)
			},
			expectedError: messagebusError,
		},
	}

	for _, tt := range tests {
		suite.Run(tt.name, func() {
			order := model.VDomain{
				ID:           types.ToPointer("domain1"),
				Name:         &domainName,
				DeletedDate:  parseTimePointer("2021-01-01"),
				RgpEppStatus: nil,
			}

			suite.SetupSuite()
			tt.mockSetup()
			logger := log.CreateChildLogger(log.Fields{
				types.LogFieldKeys.LogID:   uuid.NewString(),
				types.LogFieldKeys.JobType: "DomainPurge",
				types.LogFieldKeys.Domain:  domainName,
			})
			err := suite.service.processDomainPurge(suite.ctx, order, logger)
			if tt.expectedError != nil {
				suite.ErrorContains(err, tt.expectedError.Error())
			} else {
				suite.ErrorIs(err, nil)
			}
		})
	}
}

func (suite *DomainPurgeCronTestSuite) TestDomainDelete() {
	domainId := "domain1"
	dbError := fmt.Errorf("database error")

	tests := []struct {
		name          string
		mockSetup     func()
		expectedError error
	}{
		{
			name: "delete purgeable domain",
			mockSetup: func() {
				suite.db.On("DeleteDomainWithReason", suite.ctx, "domain1", "deleted").Return(nil)
			},
			expectedError: nil,
		},

		{
			name: "error deleting domain",
			mockSetup: func() {
				suite.db.On("DeleteDomainWithReason", suite.ctx, "domain1", "deleted").Return(dbError)
			},
			expectedError: dbError,
		},
	}

	for _, tt := range tests {
		suite.Run(tt.name, func() {
			suite.SetupSuite()
			tt.mockSetup()

			logger := log.CreateChildLogger(log.Fields{
				types.LogFieldKeys.LogID:   uuid.NewString(),
				types.LogFieldKeys.JobType: "DomainPurge",
				types.LogFieldKeys.Domain:  domainName,
			})
			err := suite.service.deleteDomain(suite.ctx, domainId, logger)
			if tt.expectedError != nil {
				suite.ErrorContains(err, tt.expectedError.Error())
			} else {
				suite.ErrorIs(err, nil)
			}
		})
	}
}
