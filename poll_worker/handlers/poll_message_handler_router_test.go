package handlers

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	"github.com/google/uuid"
	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/worker"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
)

type PollMessageTestSuite struct {
	suite.Suite
	ctx     context.Context
	db      database.Database
	cfg     config.Config
	service *WorkerService
	mb      *mocks.MockMessageBus
	s       *mocks.MockMessageBusServer
	t       *oteltrace.Tracer
}

func TestPollMessageSuite(t *testing.T) {
	suite.Run(t, new(PollMessageTestSuite))
}

func (suite *PollMessageTestSuite) SetupSuite() {
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
	suite.cfg = config
	suite.ctx = context.Background()
}

func (suite *PollMessageTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
	suite.service = NewWorkerService(suite.mb, suite.db, suite.t, suite.cfg)
}

func insertTestDomain(db database.Database, name, accreditationName, tldName string) (domain *model.Domain, accTld *model.VAccreditationTld, err error) {
	tx := db.GetDB()

	err = tx.Where("accreditation_name = ? AND tld_name = ?", accreditationName, tldName).First(&accTld).Error
	if err != nil {
		return
	}

	var tenantCustomerID string
	sql := `SELECT id FROM v_tenant_customer WHERE tenant_name= ?`
	err = tx.Raw(sql, accTld.TenantName).Scan(&tenantCustomerID).Error
	if err != nil {
		return
	}
	domain = &model.Domain{
		Name:               name,
		TenantCustomerID:   tenantCustomerID,
		AccreditationTldID: accTld.AccreditationTldID,
		RyCreatedDate:      time.Now(),
		RyExpiryDate:       time.Now(),
		ExpiryDate:         time.Now(),
	}

	err = tx.Create(domain).Error

	return
}

func insertTestProvisionDomain(db database.Database, domain *model.Domain, accTld *model.VAccreditationTld, provisionTable, cltrid, statusId string) (id string, err error) {
	tx := db.GetDB()

	switch provisionTable {
	case "provision_domain":
		tx = tx.Raw("INSERT INTO provision_domain (accreditation_id, accreditation_tld_id, tenant_customer_id, domain_name, ry_cltrid, status_id) VALUES (?,?,?,?,?,?) RETURNING id",
			accTld.AccreditationID,
			domain.AccreditationTldID,
			domain.TenantCustomerID,
			domain.Name,
			cltrid,
			statusId,
		)
	case "provision_domain_renew":
		tx = tx.Raw(
			"INSERT INTO provision_domain_renew (accreditation_id, tenant_customer_id, domain_name, domain_id, current_expiry_date, ry_expiry_date, ry_cltrid, status_id) VALUES (?,?,?,?,?,?,?,?) RETURNING id",
			accTld.AccreditationID,
			domain.TenantCustomerID,
			domain.Name,
			domain.ID,
			time.Now(),
			time.Now().AddDate(2, 0, 0),
			cltrid,
			statusId,
		)
	case "provision_domain_update":
		tx = tx.Raw(
			"INSERT INTO provision_domain_update (accreditation_id, accreditation_tld_id, tenant_customer_id, domain_name, domain_id, ry_cltrid, status_id) VALUES (?,?,?,?,?,?,?) RETURNING id",
			accTld.AccreditationID,
			domain.AccreditationTldID,
			domain.TenantCustomerID,
			domain.Name,
			domain.ID,
			cltrid,
			statusId,
		)
	default:
		tx = tx.Raw(
			fmt.Sprintf("INSERT INTO %v (accreditation_id, tenant_customer_id, domain_name, domain_id, ry_cltrid, status_id) VALUES (?,?,?,?,?,?) RETURNING id", provisionTable),
			accTld.AccreditationID,
			domain.TenantCustomerID,
			domain.Name,
			domain.ID,
			cltrid,
			statusId,
		)
	}

	err = tx.Scan(&id).Error

	return
}

func GetPollMessageText(provision_table, domain string) (msg string) {
	switch provision_table {
	case "provision_domain_redeem":
		msg = fmt.Sprintf("Restore Completed: %v", domain)
	default:
		log.Fatal("unknown provision table", nil)
	}
	return
}

func (suite *PollMessageTestSuite) TestPollMessageHandlerPendingAction() {
	tldName := "sexy"
	accreditationName := "opensrs-uniregistry"
	paMsgMap := map[uint32]string{
		0: "Pending action rejected.",
		1: "Pending action completed successfully.",
	}

	tests := []struct {
		testName  string
		tableName string
		paResult  uint32
	}{
		{
			testName:  "Approve provision domain",
			tableName: "provision_domain",
			paResult:  1,
		},
		{
			testName:  "Reject provision domain",
			tableName: "provision_domain",
			paResult:  0,
		},
		{
			testName:  "Approve provision domain update",
			tableName: "provision_domain_update",
			paResult:  1,
		},
		{
			testName:  "Reject provision domain update",
			tableName: "provision_domain_update",
			paResult:  0,
		},
		{
			testName:  "Approve provision domain renew",
			tableName: "provision_domain_renew",
			paResult:  1,
		},
		{
			testName:  "Reject provision domain renew",
			tableName: "provision_domain_renew",
			paResult:  0,
		},
		{
			testName:  "Approve provision domain redeem",
			tableName: "provision_domain_redeem",
			paResult:  1,
		},
		{
			testName:  "Reject provision domain redeem",
			tableName: "provision_domain_redeem",
			paResult:  0,
		},
	}

	for _, tt := range tests {
		suite.Run(tt.testName, func() {
			name := fmt.Sprintf("%v.%v", uuid.New().String(), tldName)
			domain, accTld, err := insertTestDomain(suite.db, name, accreditationName, tldName)
			suite.NoError(err, "Failed to create domain")
			suite.NotNil(domain)
			suite.NotNil(accTld)

			clrtid := uuid.New().String()
			statusId := suite.db.GetProvisionStatusId("pending_action")

			id, err := insertTestProvisionDomain(
				suite.db,
				domain,
				accTld,
				tt.tableName,
				clrtid,
				statusId,
			)

			suite.NoErrorf(err, "Failed to setup %v record", tt.tableName)
			suite.NotZero(id)

			msg := &worker.PollMessage{
				Id:            uuid.New().String(),
				Msg:           paMsgMap[tt.paResult],
				Type:          PollMessageType.PendingAction,
				Accreditation: accreditationName,
				Data: &worker.PollMessage_PanData{
					PanData: &ryinterface.EppPollPanData{
						Name:     name,
						PaResult: tt.paResult,
						PaCltrid: clrtid,
					},
				},
			}

			suite.s.On("Context").Return(suite.ctx)
			suite.s.On("Headers").Return(nil)

			err = suite.service.PollMessageHandler(suite.s, msg)
			suite.NoError(err, "Failed to process poll message")

			updatePD, err := suite.db.GetVProvisionDomain(suite.ctx, &model.VProvisionDomain{
				ID: &id,
			})

			if tt.paResult == 1 {
				suite.NoError(err, "Failed to get updated provision domain")
				suite.Equal(suite.db.GetProvisionStatusId("completed"), *updatePD.StatusID)
			} else {
				// failed provision records are deleted automatically
				suite.ErrorIs(err, database.ErrNotFound)
			}

			suite.mb.AssertExpectations(suite.T())
		})
	}
}

func (suite *PollMessageTestSuite) TestPollMessageHandlerUnspecPendingAction() {
	tldName := "sexy"
	accreditationName := "enom-uniregistry"

	name := fmt.Sprintf("%v.%v", uuid.New().String(), tldName)
	domain, accTld, err := insertTestDomain(suite.db, name, accreditationName, tldName)
	suite.NoError(err, "Failed to create domain")
	suite.NotNil(domain)
	suite.NotNil(accTld)

	tests := []struct {
		testName     string
		tableName    string
		successKey   string
		successValue *string
	}{
		{
			testName:     "Approve provision domain redeem",
			tableName:    "provision_domain_redeem",
			successKey:   "rgp_status",
			successValue: nil,
		},
	}

	for _, tt := range tests {
		suite.Run(tt.testName, func() {
			clrtid := uuid.New().String()
			statusId := suite.db.GetProvisionStatusId("pending_action")

			id, err := insertTestProvisionDomain(
				suite.db,
				domain,
				accTld,
				tt.tableName,
				clrtid,
				statusId,
			)

			suite.NoErrorf(err, "Failed to setup %v record", tt.tableName)
			suite.NotZero(id)

			msg := &worker.PollMessage{
				Id:            uuid.New().String(),
				Msg:           GetPollMessageText(tt.tableName, name),
				Type:          PollMessageType.Unspec,
				Accreditation: accreditationName,
			}

			suite.s.On("Context").Return(suite.ctx)
			suite.s.On("Headers").Return(nil)

			err = suite.service.PollMessageHandler(suite.s, msg)
			suite.NoError(err, "Failed to process poll message")

			// Provision status completed.
			updatePD, err := suite.db.GetVProvisionDomain(suite.ctx, &model.VProvisionDomain{
				ID: &id,
			})

			suite.NoError(err, "Failed to get updated provision domain")
			suite.Equal(suite.db.GetProvisionStatusId("completed"), *updatePD.StatusID)

			// Rgp status updated.
			updatedDomain, err := suite.db.GetVDomain(suite.ctx, &model.VDomain{
				Name: &name,
			})

			suite.NoError(err, "Failed to get updated domain")
			switch tt.successKey {
			case "rgp_status":
				suite.Equal(tt.successValue, updatedDomain.RgpEppStatus)
			default:
				log.Fatal("Invalid success key", nil)
			}

			suite.mb.AssertExpectations(suite.T())
		})
	}
}

// func (suite *PollMessageTestSuite) TestPollMessageHandlerRenewal() {
// 	tldName := "sexy"
// 	accreditationName := "opensrs-uniregistry"

// 	name := fmt.Sprintf("%v.%v", uuid.New().String(), tldName)
// 	domain, _, err := insertTestDomain(suite.db, name, accreditationName, tldName)
// 	if err != nil {
// 		return
// 	}

// 	expectedRgpEppStatus := "autoRenewPeriod"
// 	expectedExDate := time.Now().AddDate(1, 0, 0)

// 	msg := &worker.PollMessage{
// 		Id:            uuid.New().String(),
// 		Msg:           fmt.Sprintf("Auto Renew Notice: %v", name),
// 		Type:          PollMessageType.Renewal,
// 		Accreditation: accreditationName,
// 		Data: &worker.PollMessage_RenData{
// 			RenData: &ryinterface.EppPollRenData{
// 				Name:   name,
// 				ExDate: timestamppb.New(expectedExDate),
// 			},
// 		},
// 	}

// 	suite.s.On("Context").Return(suite.ctx)

// 	err = suite.service.PollMessageHandler(suite.s, msg)
// 	suite.NoError(err, "Failed to process poll message")

// 	updatedDomain, err := suite.db.GetVDomain(suite.ctx, &model.VDomain{Name: &name})
// 	if err != nil {
// 		return
// 	}

// 	suite.NotEqual(&domain.RyExpiryDate, updatedDomain.RyExpiryDate)
// 	suite.Equal(expectedExDate.Unix(), updatedDomain.RyExpiryDate.Unix())
// 	suite.Equal(&expectedRgpEppStatus, updatedDomain.RgpEppStatus)

// 	suite.mb.AssertExpectations(suite.T())
// }

// func (suite *PollMessageTestSuite) TestPollMessageHandlerUnspecRenewal() {
// 	tldName := "sexy"
// 	accreditationName := "enom-uniregistry"

// 	name := fmt.Sprintf("%v.%v", uuid.New().String(), tldName)
// 	domain, _, err := insertTestDomain(suite.db, name, accreditationName, tldName)
// 	if err != nil {
// 		return
// 	}

// 	expectedRgpEppStatus := "autoRenewPeriod"
// 	expectedExDate := time.Now().AddDate(1, 0, 0)
// 	expectedContext := suite.ctx
// 	expectedDestination := types.GetQueryQueue(accreditationName)
// 	expectedMsg := ryinterface.DomainInfoRequest{
// 		Name: name,
// 	}
// 	expectedHeaders := map[string]any{}

// 	domainInfoResponse := ryinterface.DomainInfoResponse{
// 		Name:       name,
// 		ExpiryDate: timestamppb.New(expectedExDate),
// 	}

// 	expResponse := messagebus.RpcResponse{
// 		Server:  nil,
// 		Message: &domainInfoResponse,
// 	}

// 	suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), expectedDestination, &expectedMsg, expectedHeaders).Return("test_id", expResponse, nil)
// 	suite.s.On("MessageBus").Return(suite.mb)
// 	suite.s.On("Context").Return(expectedContext)

// 	msg := &worker.PollMessage{
// 		Id:            uuid.New().String(),
// 		Msg:           fmt.Sprintf("M085: Domain %v (ABC-US) auto-renewed", name),
// 		Type:          PollMessageType.Unspec,
// 		Accreditation: accreditationName,
// 	}

// 	err = suite.service.PollMessageHandler(suite.s, msg)
// 	suite.NoError(err, "Failed to process poll message")

// 	updatedDomain, err := suite.db.GetVDomain(expectedContext, &model.VDomain{Name: &name})
// 	if err != nil {
// 		return
// 	}

// 	suite.NotEqual(&domain.RyExpiryDate, updatedDomain.RyExpiryDate)
// 	suite.Equal(expectedExDate.Unix(), updatedDomain.RyExpiryDate.Unix())
// 	suite.Equal(&expectedRgpEppStatus, updatedDomain.RgpEppStatus)

// 	suite.mb.AssertExpectations(suite.T())
// }

func (suite *PollMessageTestSuite) TestPollMessageHandlerUnknown() {

	msg := &worker.PollMessage{
		Id:            uuid.New().String(),
		Msg:           "Pending action completed successfully.",
		Type:          "Invalid",
		Accreditation: "opensrs-uniregistry",
		Data: &worker.PollMessage_PanData{
			PanData: &ryinterface.EppPollPanData{
				Name:     "test.com",
				PaResult: 1,
				PaCltrid: "TEST-ID",
			},
		},
	}

	suite.s.On("Context").Return(suite.ctx)
	suite.s.On("Headers").Return(nil)

	err := suite.service.PollMessageHandler(suite.s, msg)
	suite.ErrorContains(err, "unknown poll message")

	suite.mb.AssertExpectations(suite.T())
}

func (suite *PollMessageTestSuite) TestPollMessageHandlerNotFound() {

	msg := &worker.PollMessage{
		Id:            uuid.New().String(),
		Msg:           "Pending action completed successfully.",
		Type:          "pending_action",
		Accreditation: "opensrs-uniregistry",
		Data: &worker.PollMessage_PanData{
			PanData: &ryinterface.EppPollPanData{
				Name:     "test.com",
				PaResult: 1,
				PaCltrid: "TEST-ID",
			},
		},
	}

	suite.s.On("Context").Return(suite.ctx)
	suite.s.On("Headers").Return(nil)

	err := suite.service.PollMessageHandler(suite.s, msg)
	suite.NoError(err)

	suite.mb.AssertExpectations(suite.T())
}
