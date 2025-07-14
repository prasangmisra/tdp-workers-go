package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/suite"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	jobmessage "github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"

	commonmessages "github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/timestamppb"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

func TestDomainRenewTestSuite(t *testing.T) {
	suite.Run(t, new(DomainRenewTestSuite))
}

type DomainRenewTestSuite struct {
	suite.Suite
	db     database.Database
	mb     *mocks.MockMessageBus
	s      *mocks.MockMessageBusServer
	tracer *oteltrace.Tracer
}

func (suite *DomainRenewTestSuite) SetupSuite() {
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

func (suite *DomainRenewTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertTestDomain(db database.Database, name string) (domain *model.Domain, err error) {
	tx := db.GetDB()

	var tenantCustomerID string
	err = tx.Table("tenant_customer").Select("id").Scan(&tenantCustomerID).Error
	if err != nil {
		return
	}

	var accreditationTldID *string
	err = tx.Table("accreditation_tld").Select("id").Scan(&accreditationTldID).Error
	if err != nil {
		return
	}

	createdDate := time.Now()
	expiryDate := createdDate.AddDate(1, 0, 0)

	domain = &model.Domain{
		Name:               name,
		TenantCustomerID:   tenantCustomerID,
		AccreditationTldID: accreditationTldID,
		RyCreatedDate:      createdDate,
		RyExpiryDate:       expiryDate,
		ExpiryDate:         expiryDate,
	}

	err = tx.Create(domain).Error

	return
}

func insertProvisionDomainRenewTest(db database.Database, domain *model.Domain) (id string, err error) {
	tx := db.GetDB()

	var accreditationID string
	err = tx.Table("accreditation_tld").Select("accreditation_id").Where("id = ?", domain.AccreditationTldID).Scan(&accreditationID).Error
	if err != nil {
		return
	}

	currentExpiryDate := domain.RyExpiryDate.Format(ExpiryDateFormat)

	err = tx.Raw(
		"INSERT INTO provision_domain_renew (accreditation_id, tenant_customer_id, domain_id, domain_name, current_expiry_date, status_id) VALUES (?,?,?,?,?,?) RETURNING id",
		accreditationID,
		domain.TenantCustomerID,
		domain.ID,
		domain.Name,
		currentExpiryDate,
		db.GetProvisionStatusId("pending"),
	).Scan(&id).Error

	return
}

func insertDomainRenewTestJob(db database.Database, withPrice bool) (jobId string, data *types.DomainRenewData, err error) {
	tx := db.GetDB()

	domain, err := insertTestDomain(db, fmt.Sprintf("example%s.help", uuid.New().String()))
	if err != nil {
		return
	}

	provisionDomainRenewId, err := insertProvisionDomainRenewTest(db, domain)
	if err != nil {
		return
	}

	expiryDate, _ := time.Parse(ExpiryDateFormat, domain.RyExpiryDate.Format(ExpiryDateFormat))

	data = &types.DomainRenewData{
		Name:                   domain.Name,
		ProvisionDomainRenewId: provisionDomainRenewId,
		TenantCustomerId:       domain.TenantCustomerID,
		Period:                 types.ToPointer(uint32(1)),
		ExpiryDate:             &expiryDate,
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

	if withPrice {
		data.Price = &types.OrderPrice{Amount: 1045, Currency: "USD", Fraction: 100}
	}

	serializedData, err := json.Marshal(data)
	if err != nil {
		return
	}

	sql := `SELECT job_submit(?,?,?,?)`
	err = tx.Raw(sql, domain.TenantCustomerID, "provision_domain_renew", provisionDomainRenewId, serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	return
}

func (suite *DomainRenewTestSuite) TestDomainRenewHandler() {
	jobId, data, err := insertDomainRenewTestJob(suite.db, false)
	suite.NoError(err, "Failed to insert test job")

	msg := &jobmessage.Notification{
		JobId:          jobId,
		Type:           "domain_renew",
		Status:         "status",
		ReferenceId:    data.ProvisionDomainRenewId,
		ReferenceTable: "1234",
	}

	expectedContext := context.Background()
	expectedDestination := types.GetTransformQueue(accreditationName)
	expectedMsg := ryinterface.DomainRenewRequest{
		Name:              data.Name,
		Period:            *data.Period,
		PeriodUnit:        commonmessages.PeriodUnit_YEAR,
		CurrentExpiryDate: timestamppb.New(*data.ExpiryDate),
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

	handler := service.DomainRenewHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}

func (suite *DomainRenewTestSuite) TestDomainRenewHandlerWithPrice() {
	jobId, data, err := insertDomainRenewTestJob(suite.db, true)
	suite.NoError(err, "Failed to insert test job")

	msg := &jobmessage.Notification{
		JobId:          jobId,
		Type:           "domain_renew",
		Status:         "status",
		ReferenceId:    data.ProvisionDomainRenewId,
		ReferenceTable: "1234",
	}

	expectedContext := context.Background()
	expectedDestination := types.GetTransformQueue(accreditationName)
	expectedExtension, _ := anypb.New(&extension.FeeTransformRequest{Fee: []*extension.FeeFee{{Price: &commonmessages.Money{CurrencyCode: "USD", Units: 10, Nanos: 450000000}}}})
	expectedMsg := ryinterface.DomainRenewRequest{
		Name:              data.Name,
		Period:            *data.Period,
		PeriodUnit:        commonmessages.PeriodUnit_YEAR,
		CurrentExpiryDate: timestamppb.New(*data.ExpiryDate),
		Extensions:        map[string]*anypb.Any{"fee": expectedExtension},
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

	handler := service.DomainRenewHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}
