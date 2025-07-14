package handlers

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/suite"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	jobmessage "github.com/tucowsinc/tdp-messages-go/message/job"
	rymessages "github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

func TestDomainInfoTestSuite(t *testing.T) {
	suite.Run(t, new(DomainInfoTestSuite))
}

type DomainInfoTestSuite struct {
	suite.Suite
	db     database.Database
	mb     *mocks.MockMessageBus
	s      *mocks.MockMessageBusServer
	tracer *oteltrace.Tracer
}

func (suite *DomainInfoTestSuite) SetupSuite() {
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

	db, err := database.New(cfg.PostgresPoolConfig(), cfg.GetDBLogLevel())
	suite.NoError(err, types.LogMessages.DatabaseConnectionFailed)
	suite.db = db
}

func (suite *DomainInfoTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertDomainTransferInTestJob(db database.Database) (jobId string, data *types.DomainTransferInData, err error) {
	tx := db.GetDB()

	var tcId string
	err = tx.Table("tenant_customer").Select("id").Scan(&tcId).Error
	if err != nil {
		return
	}

	data = &types.DomainTransferInData{
		Name:             "test-domain.sexy",
		TenantCustomerId: tcId,
		Accreditation: types.Accreditation{
			IsProxy:              false,
			TenantId:             "test_tenantId",
			TenantName:           "test_tenantName",
			ProviderId:           "test_providerId",
			ProviderName:         "test_providerName",
			AccreditationId:      "test_accreditationId",
			AccreditationName:    accreditationName,
			ProviderInstanceId:   "test_providerInstanceId",
			ProviderInstanceName: "test_providerInstanceName",
		},
	}
	serializedData, err := json.Marshal(data)
	if err != nil {
		return
	}

	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, tcId, "provision_domain_transfer_in", "0268f162-5d83-44d2-894a-ab7578c498fb", serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	return
}

func insertValidateDomainTransferableTestJob(db database.Database) (jobId string, data types.DomainTransferValidationData, err error) {
	tx := db.GetDB()

	//get a tenant id (doesn't matter which)
	//automatically generated when db is brought up
	var id string
	err = tx.Table("tenant_customer").Select("id").Scan(&id).Error
	if err != nil {
		return
	}

	data = types.DomainTransferValidationData{
		Name:             "test_domain.com",
		OrderItemPlanId:  uuid.New().String(),
		TenantCustomerId: id,
		Accreditation: types.Accreditation{
			IsProxy:           false,
			AccreditationName: accreditationName,
		},
	}

	serializedData, _ := json.Marshal(data)

	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, id, "validate_domain_transferable", data.OrderItemPlanId, serializedData).Scan(&jobId).Error

	return
}

func insertDomainExpiryDateTestJob(db database.Database) (jobId string, data *types.DomainRenewData, err error) {
	tx := db.GetDB()

	var tenantCustomerID string
	err = tx.Table("tenant_customer").Select("id").Scan(&tenantCustomerID).Error
	if err != nil {
		return
	}

	data = &types.DomainRenewData{
		Name:                   "test_domain",
		Period:                 types.ToPointer(uint32(1)),
		ExpiryDate:             types.ToPointer(time.Now().AddDate(1, 0, 0)),
		ProvisionDomainRenewId: "0268f162-5d83-44d2-894a-ab7578c498fb",
		TenantCustomerId:       tenantCustomerID,
		Accreditation: types.Accreditation{
			IsProxy:              false,
			TenantId:             "test_tenantId",
			TenantName:           "test_tenantName",
			ProviderId:           "test_providerId",
			ProviderName:         "test_providerName",
			AccreditationId:      "test_accreditationId",
			AccreditationName:    accreditationName,
			ProviderInstanceId:   "test_providerInstanceId",
			ProviderInstanceName: "test_providerInstanceName",
		},
	}

	serializedData, err := json.Marshal(data)
	if err != nil {
		return
	}

	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, tenantCustomerID, "setup_domain_renew", "0268f162-5d83-44d2-894a-ab7578c498fb", serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	return
}

func insertDomainHostsTestJob(db database.Database) (jobId string, data *types.DomainDeleteData, err error) {
	tx := db.GetDB()

	var tenantCustomerID string
	err = tx.Table("tenant_customer").Select("id").Scan(&tenantCustomerID).Error
	if err != nil {
		return
	}

	data = &types.DomainDeleteData{
		Name:                    "test_domain",
		ProvisionDomainDeleteId: "0268f162-5d83-44d2-894a-ab7578c498fb",
		TenantCustomerId:        tenantCustomerID,
		Accreditation: types.Accreditation{
			IsProxy:              false,
			TenantId:             "test_tenantId",
			TenantName:           "test_tenantName",
			ProviderId:           "test_providerId",
			ProviderName:         "test_providerName",
			AccreditationId:      "test_accreditationId",
			AccreditationName:    accreditationName,
			ProviderInstanceId:   "test_providerInstanceId",
			ProviderInstanceName: "test_providerInstanceName",
		},
	}

	serializedData, err := json.Marshal(data)
	if err != nil {
		return
	}

	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, tenantCustomerID, "setup_domain_delete", "0268f162-5d83-44d2-894a-ab7578c498fb", serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	return
}

func (suite *DomainInfoTestSuite) TestDomainInfoHandler_DomainTransferIn() {
	jobId, data, err := insertDomainTransferInTestJob(suite.db)
	suite.NoError(err, "Failed to insert domain transfer in test job")

	msg := &jobmessage.Notification{
		JobId:          jobId,
		Type:           "provision_domain_transfer_in",
		Status:         "submitted",
		ReferenceId:    "",
		ReferenceTable: "provision_domain_transfer_in",
	}

	expectedContext := context.Background()
	expectedDestination := types.GetQueryQueue(accreditationName)
	expectedMsg := rymessages.DomainInfoRequest{
		Name: data.Name,
	}
	expectedHeaders := map[string]any{
		"reply_to":       "WorkerJobDomainProvisionUpdate",
		"correlation_id": jobId,
	}

	service := NewWorkerService(suite.mb, suite.db, suite.tracer)

	suite.mb.On("Send", expectedContext, expectedDestination, &expectedMsg, expectedHeaders).Return(nil)
	suite.s.On("MessageBus").Return(suite.mb)
	suite.s.On("Headers").Return(expectedHeaders)
	suite.s.On("Context").Return(expectedContext)

	handler := service.DomainInfoHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}

func (suite *DomainInfoTestSuite) TestDomainInfoHandler_ValidateDomainTransferable() {
	jobId, data, err := insertValidateDomainTransferableTestJob(suite.db)
	suite.NoError(err, "Failed to insert test job")

	msg := &jobmessage.Notification{
		JobId:          jobId,
		Type:           "validate_domain_transferable",
		Status:         "submitted",
		ReferenceId:    data.OrderItemPlanId,
		ReferenceTable: "order_item_plan",
	}

	expectedContext := context.Background()
	expectedDestination := types.GetQueryQueue(accreditationName)
	expectedMsg := rymessages.DomainInfoRequest{
		Name: data.Name,
		Pw:   &data.Pw,
	}
	expectedHeaders := map[string]any{
		"reply_to":       "WorkerJobDomainProvisionUpdate",
		"correlation_id": jobId,
	}

	service := NewWorkerService(suite.mb, suite.db, suite.tracer)

	suite.mb.On("Send", expectedContext, expectedDestination, &expectedMsg, expectedHeaders).Return(nil)
	suite.s.On("MessageBus").Return(suite.mb)
	suite.s.On("Headers").Return(expectedHeaders)
	suite.s.On("Context").Return(expectedContext)

	handler := service.DomainInfoHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}

func (suite *DomainInfoTestSuite) TestDomainInfoHandler_DomainExpiryDateCheck() {
	jobId, data, err := insertDomainExpiryDateTestJob(suite.db)
	suite.NoError(err, "Failed to insert test job")

	msg := &jobmessage.Notification{
		JobId:          jobId,
		Type:           "setup_domain_renew",
		Status:         "submitted",
		ReferenceId:    "",
		ReferenceTable: "",
	}

	expectedContext := context.Background()
	expectedDestination := types.GetQueryQueue(accreditationName)
	expectedMsg := rymessages.DomainInfoRequest{
		Name: data.Name,
	}
	expectedHeaders := map[string]any{
		"reply_to":       "WorkerJobDomainProvisionUpdate",
		"correlation_id": jobId,
	}

	service := NewWorkerService(suite.mb, suite.db, suite.tracer)

	suite.mb.On("Send", expectedContext, expectedDestination, &expectedMsg, expectedHeaders).Return(nil)
	suite.s.On("MessageBus").Return(suite.mb)
	suite.s.On("Headers").Return(expectedHeaders)
	suite.s.On("Context").Return(expectedContext)

	handler := service.DomainInfoHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}

func (suite *DomainInfoTestSuite) TestDomainInfoHandler_DomainHostsCheck() {
	jobId, data, err := insertDomainHostsTestJob(suite.db)
	suite.NoError(err, "Failed to insert test job")

	msg := &jobmessage.Notification{
		JobId:          jobId,
		Type:           "setup_domain_delete",
		Status:         "submitted",
		ReferenceId:    "",
		ReferenceTable: "",
	}

	expectedContext := context.Background()
	expectedDestination := types.GetQueryQueue(accreditationName)
	expectedMsg := rymessages.DomainInfoRequest{
		Name: data.Name,
	}
	expectedHeaders := map[string]any{
		"reply_to":       "WorkerJobDomainProvisionUpdate",
		"correlation_id": jobId,
	}

	service := NewWorkerService(suite.mb, suite.db, suite.tracer)

	suite.mb.On("Send", expectedContext, expectedDestination, &expectedMsg, expectedHeaders).Return(nil)
	suite.s.On("MessageBus").Return(suite.mb)
	suite.s.On("Headers").Return(expectedHeaders)
	suite.s.On("Context").Return(expectedContext)

	handler := service.DomainInfoHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}
