package handlers

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	certmessages "github.com/tucowsinc/tdp-messages-go/message/certbot"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type CertificateRenewResponseTestSuite struct {
	suite.Suite
	ctx     context.Context
	db      database.Database
	cfg     config.Config
	service *WorkerService
	mb      *mocks.MockMessageBus
	s       *mocks.MockMessageBusServer
	t       *oteltrace.Tracer
}

func TestCertificateRenewResponseSuite(t *testing.T) {
	suite.Run(t, new(CertificateRenewResponseTestSuite))
}

func (suite *CertificateRenewResponseTestSuite) SetupSuite() {
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
	suite.cfg = cfg
	suite.ctx = context.Background()
}

func (suite *CertificateRenewResponseTestSuite) SetupTest() {
	suite.service = NewWorkerService(suite.mb, suite.db, suite.t)
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertHostingTestItem(db database.Database, hostingId string, domain string) (err error) {
	tx := db.GetDB()

	var tenantId string
	if err = tx.Table("tenant_customer").Select("id").Scan(&tenantId).Error; err != nil {
		return
	}

	var productId string
	if err = tx.Table("hosting_product").Select("id").Scan(&productId).Error; err != nil {
		return
	}

	var regionId string
	if err = tx.Table("hosting_region").Select("id").Scan(&regionId).Error; err != nil {
		return
	}

	var clientId string
	if err = tx.Table("hosting_client").Select("id").Scan(&clientId).Error; err != nil {
		return
	}

	err = tx.Exec(`INSERT INTO hosting (id, tenant_customer_id, domain_name, product_id, region_id, client_id, is_active, is_deleted) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`, hostingId, tenantId, domain, productId, regionId, clientId, true, false).Error
	return
}

func getProvisionHostingUpdate(db database.Database, hostingId string) (result *model.ProvisionHostingUpdate, err error) {
	tx := db.GetDB()

	sql := `SELECT * FROM provision_hosting_update WHERE hosting_id = ?`
	err = tx.Raw(sql, hostingId).Scan(&result).Error
	return
}

func (suite *CertificateRenewResponseTestSuite) TestCertificateRenewResponseHandler() {
	ctx := context.Background()
	hostingId := uuid.NewString()
	domain := getTestDomainName()

	err := insertHostingTestItem(suite.db, hostingId, domain)
	suite.NoError(err, "failed to insert hosting item")

	testData := certmessages.CertificateRenewedNotification{
		Certificate: &certmessages.Certificate{
			Cert:       "test-cert",
			Chain:      "test-chain",
			PrivateKey: "test-private-key",
			NotBefore:  timestamppb.Now(),
			NotAfter:   timestamppb.Now(),
		},
		RequestId: hostingId,
		Domain:    domain,
		Status:    certmessages.CertStatus_CERT_STATUS_SUCCESS,
		Message:   "test-message",
	}

	suite.s.On("Context").Return(ctx)
	suite.s.On("Headers").Return(nil)

	err = suite.service.CertificateRenewResponseHandler(suite.s, &testData)
	suite.NoError(err, "failed to handle certificate renew response")

	_, err = getProvisionHostingUpdate(suite.db, hostingId)
	suite.NoError(err, "failed to get provision record")
}

func (suite *CertificateRenewResponseTestSuite) TestCertificateRenewResponseHandlerErrorStatus() {
	ctx := context.Background()
	hostingId := uuid.NewString()
	domain := getTestDomainName()

	err := insertHostingTestItem(suite.db, hostingId, domain)
	suite.NoError(err, "failed to insert hosting item")

	testData := certmessages.CertificateRenewedNotification{
		Certificate: &certmessages.Certificate{
			Cert:       "test-cert",
			Chain:      "test-chain",
			PrivateKey: "test-private-key",
			NotBefore:  timestamppb.Now(),
			NotAfter:   timestamppb.Now(),
		},
		RequestId: hostingId,
		Domain:    domain,
		Status:    certmessages.CertStatus_CERT_STATUS_ERROR,
		Message:   "test-error-message",
	}

	suite.s.On("Context").Return(ctx)
	suite.s.On("Headers").Return(nil)

	err = suite.service.CertificateRenewResponseHandler(suite.s, &testData)
	suite.NoError(err, "failed to handle certificate renew response")

	hosting, err := suite.db.GetHosting(ctx, &model.Hosting{ID: hostingId})
	suite.NoError(err, "failed to get hosting")
	suite.Equal("Failed Certificate Renewal", suite.db.GetHostingStatusName(types.SafeDeref(hosting.HostingStatusID)))
}

func (suite *CertificateRenewResponseTestSuite) TestCertificateRenewResponseHandler_RealWorldFallbackScenario() {
	ctx := context.Background()

	oldHostingId := uuid.NewString()
	newHostingId := uuid.NewString()
	domain := getTestDomainName()

	err := insertHostingTestItem(suite.db, newHostingId, domain)
	suite.NoError(err, "failed to insert new hosting for fallback")

	testData := certmessages.CertificateRenewedNotification{
		Certificate: &certmessages.Certificate{
			Cert:       "cert-body-fallback",
			Chain:      "cert-chain-fallback",
			PrivateKey: "cert-private-key-fallback",
			NotBefore:  timestamppb.Now(),
			NotAfter:   timestamppb.Now(),
		},
		RequestId: oldHostingId, // this will fail lookup
		Domain:    domain,       // fallback match
		Status:    certmessages.CertStatus_CERT_STATUS_SUCCESS,
		Message:   "renewal via fallback",
	}

	suite.s.On("Context").Return(ctx)
	suite.s.On("Headers").Return(nil)

	err = suite.service.CertificateRenewResponseHandler(suite.s, &testData)
	suite.NoError(err, "handler should fallback from request ID to domain and succeed")

	// Verify order was created using newHostingId
	var order model.Order
	tx := suite.db.GetDB()
	err = tx.Table("order").
		Preload("OrderItemUpdateHosting").
		Where("tenant_customer_id = (?)",
			tx.Table("hosting").Select("tenant_customer_id").Where("id = ?", newHostingId),
		).
		Order("created_date DESC").
		First(&order).Error

	suite.NoError(err, "expected fallback to create order using new hosting")

	suite.Equal(newHostingId, order.OrderItemUpdateHosting.HostingID, "fallback to domain should use new hosting ID")
}
