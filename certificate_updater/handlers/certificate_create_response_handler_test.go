package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	certmessages "github.com/tucowsinc/tdp-messages-go/message/certbot"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

type OrderItem struct {
	Object string  `json:"object"`
	Status string  `json:"status"`
	Error  *string `json:"error"`
}

type OrderNotification struct {
	OrderId     string       `json:"order_id"`
	OrderStatus string       `json:"order_status_name"`
	OrderItems  *[]OrderItem `json:"order_item_plans"`
}

type CertificateProvisionResponseTestSuite struct {
	suite.Suite
	ctx     context.Context
	db      database.Database
	service *WorkerService
	mb      *mocks.MockMessageBus
	s       *mocks.MockMessageBusServer
	t       *oteltrace.Tracer
}

func TestCertificateProvisionResponseSuite(t *testing.T) {
	suite.Run(t, new(CertificateProvisionResponseTestSuite))
}

func (suite *CertificateProvisionResponseTestSuite) SetupSuite() {
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
	suite.ctx = context.Background()
}

func (suite *CertificateProvisionResponseTestSuite) SetupTest() {
	suite.service = NewWorkerService(suite.mb, suite.db, suite.t)
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func getTestDomainName() string {
	return fmt.Sprintf("%s.sexy", uuid.New().String())
}

func insertCertificateProvisionTestJob(db database.Database, domain string) (job *model.Job, provisionId string, hostingId string, orderId string, err error) {
	tx := db.GetDB()

	// create test order
	err = tx.Raw(`
		INSERT INTO "order"
			(tenant_customer_id, type_id)
			VALUES ((SELECT id FROM tenant_customer LIMIT 1), 
			(SELECT id FROM v_order_type WHERE product_name='hosting' AND name='create'))
			RETURNING id
	`).Scan(&orderId).Error
	if err != nil {
		return
	}

	var hostingClientId string

	// create test order_items
	err = tx.Raw(`
		INSERT INTO order_item_create_hosting_client(
            tenant_customer_id,
            email
        ) VALUES(
            (SELECT id FROM tenant_customer LIMIT 1),
            'test@email.com'
        ) RETURNING id 
	`).Scan(&hostingClientId).Error
	if err != nil {
		return
	}

	err = tx.Raw(`
		INSERT INTO order_item_create_hosting(
        order_id,
        tenant_customer_id,
        client_id,
        domain_name,
        product_id,
        region_id
		) VALUES(
			$1::UUID,
			(SELECT id FROM tenant_customer LIMIT 1),
			$2::UUID,
			$3,
			tc_id_from_name('hosting_product','Wordpress'),
			tc_id_from_name('hosting_region', 'US East (N. Virginia)')
		) RETURNING id
	`, orderId, hostingClientId, domain).Scan(&hostingId).Error
	if err != nil {
		return
	}

	tx.Exec(`UPDATE "order" SET status_id = tc_id_from_name('order_status', 'processing') WHERE id=$1`, orderId)

	tx.Raw(`SELECT id FROM provision_hosting_certificate_create WHERE domain_name = $1`, domain).Scan(&provisionId)

	var jobId string
	tx.Raw(`SELECT job_id FROM provision_hosting_certificate_create WHERE id = $1`, provisionId).Scan(&jobId)

	tx.Exec(`UPDATE job SET status_id = tc_id_from_name('job_status', 'completed') WHERE parent_id = $1`, jobId)

	tx.Exec(`UPDATE job SET status_id = tc_id_from_name('job_status', 'completed_conditionally') WHERE id = $1`, jobId)

	job, err = db.GetJobById(context.Background(), jobId, false)
	if err != nil {
		return
	}
	return
}

func getOrderNotification(db database.Database, order *model.Order) (notification *OrderNotification, err error) {
	tx := db.GetDB()

	var data = new(struct {
		Value []byte `json:"value"`
	})

	err = tx.Raw("select build_order_notification_payload($1) as value", order.ID).Scan(&data).Error
	if err != nil {
		return
	}

	err = json.Unmarshal(data.Value, &notification)
	if err != nil {
		log.Error(types.LogMessages.JSONDecodeFailed, log.Fields{
			types.LogFieldKeys.Error: err.Error(),
		})
		return
	}

	return
}

func (n OrderNotification) getError() (error *string) {
	if n.OrderItems == nil {
		return
	}

	var errs []string
	for _, i := range *n.OrderItems {
		if i.Error != nil {
			errs = append(errs, *i.Error)
		}
	}
	if errs == nil {
		return
	}

	err := strings.Join(errs, ";")
	return &err
}

func (suite *CertificateProvisionResponseTestSuite) TestCertificateProvisionResponseHandler() {
	// create test job
	testDomain := getTestDomainName()

	job, provisionId, hostingId, _, err := insertCertificateProvisionTestJob(suite.db, testDomain)
	suite.NoError(err, "Failed to insert test job")

	// need to add timestamps to the test data
	testData := certmessages.CertificateIssuedNotification{
		Certificate: &certmessages.Certificate{
			Cert:       "test-cert",
			Chain:      "test-chain",
			PrivateKey: "test-private-key",
			NotBefore:  timestamppb.Now(),
			NotAfter:   timestamppb.Now(),
		},
		RequestId: hostingId,
		Domain:    testDomain,
		Status:    certmessages.CertStatus_CERT_STATUS_SUCCESS,
		Message:   "test-message",
	}

	suite.s.On("Context").Return(suite.ctx)
	suite.s.On("Headers").Return(nil)

	err = suite.service.CertificateCreateResponseHandler(suite.s, &testData)
	suite.NoError(err, "failed to handle response")

	// check and make sure provision record was updated correctly
	resJob, err := suite.db.GetJobById(suite.ctx, job.ID, false)
	suite.NoError(err, "failed to get test job")
	suite.Equal(types.JobStatus.CompletedConditionally, suite.db.GetJobStatusName(resJob.StatusID))

	var provisionRecord model.ProvisionHostingCertificateCreate
	err = suite.db.GetDB().Where("id = ?", provisionId).First(&provisionRecord).Error
	suite.NoError(err, "failed to get provision record")

	suite.Equal(testData.Certificate.Cert, *provisionRecord.Body)
	suite.Equal(testData.Certificate.Chain, *provisionRecord.Chain)
	suite.Equal(testData.Certificate.PrivateKey, *provisionRecord.PrivateKey)
	suite.Equal(testData.Certificate.NotBefore.AsTime().Round(time.Second), provisionRecord.NotBefore.UTC().Round(time.Second))
	suite.Equal(testData.Certificate.NotAfter.AsTime().Round(time.Second), provisionRecord.NotAfter.UTC().Round(time.Second))
}

func (suite *CertificateProvisionResponseTestSuite) TestCertificateProvisionResponseHandlerNoRequestId() {
	// create test job
	testDomain := getTestDomainName()

	job, provisionId, _, _, err := insertCertificateProvisionTestJob(suite.db, testDomain)
	suite.NoError(err, "Failed to insert test job")

	// need to add timestamps to the test data
	testData := certmessages.CertificateIssuedNotification{
		Certificate: &certmessages.Certificate{
			Cert:       "test-cert",
			Chain:      "test-chain",
			PrivateKey: "test-private-key",
			NotBefore:  timestamppb.Now(),
			NotAfter:   timestamppb.Now(),
		},
		Domain:  testDomain,
		Status:  certmessages.CertStatus_CERT_STATUS_SUCCESS,
		Message: "test-message",
	}

	suite.s.On("Context").Return(suite.ctx)
	suite.s.On("Headers").Return(nil)

	err = suite.service.CertificateCreateResponseHandler(suite.s, &testData)
	suite.NoError(err, "failed to handle response")

	// check and make sure provision record was updated correctly
	resJob, err := suite.db.GetJobById(suite.ctx, job.ID, false)
	suite.NoError(err, "failed to get test job")
	suite.Equal(types.JobStatus.CompletedConditionally, suite.db.GetJobStatusName(resJob.StatusID))

	var provisionRecord model.ProvisionHostingCertificateCreate
	err = suite.db.GetDB().Where("id = ?", provisionId).First(&provisionRecord).Error
	suite.NoError(err, "failed to get provision record")

	suite.Equal(testData.Certificate.Cert, *provisionRecord.Body)
	suite.Equal(testData.Certificate.Chain, *provisionRecord.Chain)
	suite.Equal(testData.Certificate.PrivateKey, *provisionRecord.PrivateKey)
	suite.Equal(testData.Certificate.NotBefore.AsTime().Round(time.Second), provisionRecord.NotBefore.UTC().Round(time.Second))
	suite.Equal(testData.Certificate.NotAfter.AsTime().Round(time.Second), provisionRecord.NotAfter.UTC().Round(time.Second))
}

func (suite *CertificateProvisionResponseTestSuite) TestCertificateProvisionResponseHandlerErrorStatus() {
	// create test job
	testDomain := getTestDomainName()

	_, _, hostingId, orderId, err := insertCertificateProvisionTestJob(suite.db, testDomain)
	suite.NoError(err, "Failed to insert test job")

	testData := certmessages.CertificateIssuedNotification{
		Certificate: &certmessages.Certificate{
			Cert:       "test-cert",
			Chain:      "test-chain",
			PrivateKey: "test-private-key",
			NotBefore:  timestamppb.Now(),
			NotAfter:   timestamppb.Now(),
		},
		RequestId: hostingId,
		Domain:    testDomain,
		Status:    certmessages.CertStatus_CERT_STATUS_ERROR,
		Message:   "test-error-message",
	}

	suite.s.On("Context").Return(suite.ctx)
	suite.s.On("Headers").Return(nil)

	err = suite.service.CertificateCreateResponseHandler(suite.s, &testData)
	suite.NoError(err, "failed to handle response")

	notif, err := getOrderNotification(suite.db, &model.Order{ID: orderId})
	suite.NoError(err, "failed to get order error message")

	suite.Equal(testData.Message, *notif.getError())
	suite.Equal(types.OrderStatusEnum.Failed, notif.OrderStatus)
}
