package handlers

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/lib/pq"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message"
	commonmessages "github.com/tucowsinc/tdp-messages-go/message/common"
	rymessages "github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"

	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

func TestRyDomainTransferInHandler(t *testing.T) {
	suite.Run(t, new(RyDomainTransferInTestSuite))
}

type RyDomainTransferInTestSuite struct {
	suite.Suite
	db     database.Database
	mb     *mocks.MockMessageBus
	s      *mocks.MockMessageBusServer
	tracer *oteltrace.Tracer
}

func (suite *RyDomainTransferInTestSuite) SetupSuite() {
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

func (suite *RyDomainTransferInTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertRyDomainTransferInTestJob(db database.Database) (job *model.Job, pdti *model.ProvisionDomainTransferIn, err error) {

	// Insert provision domain transfer in request job
	_, pdtr, err := insertRyDomainTransferInRequestTestJob(db)
	if err != nil {
		return
	}

	tx := db.GetDB()

	var tcId string
	err = tx.Table("tenant_customer").Select("id").Scan(&tcId).Error
	if err != nil {
		return
	}

	type accreditation struct {
		Id   string `json:"id"`
		Name string `json:"name"`
	}

	acc := accreditation{}

	err = tx.Table("accreditation").Select("id", "name").Scan(&acc).Error
	if err != nil {
		return
	}

	var accTldId string
	err = tx.Table("accreditation_tld").Select("id").Scan(&accTldId).Error
	if err != nil {
		return
	}

	pdti = &model.ProvisionDomainTransferIn{
		DomainName:                 "test-domain.sexy",
		AccreditationID:            acc.Id,
		AccreditationTldID:         accTldId,
		TenantCustomerID:           tcId,
		StatusID:                   db.GetProvisionStatusId("processing"),
		ProvisionTransferRequestID: types.ToPointer(pdtr.ID),
	}

	err = tx.Create(pdti).Error
	if err != nil {
		return
	}

	data := &types.DomainTransferInData{
		Name:             "test-domain.sexy",
		TenantCustomerId: tcId,
		Accreditation: types.Accreditation{
			IsProxy:              false,
			TenantId:             "test_tenantId",
			TenantName:           "test_tenantName",
			ProviderId:           "test_providerId",
			ProviderName:         "test_providerName",
			AccreditationId:      acc.Id,
			AccreditationName:    acc.Name,
			ProviderInstanceId:   "test_providerInstanceId",
			ProviderInstanceName: "test_providerInstanceName",
		},
		ProvisionDomainTransferInId: pdti.ID,
	}

	serializedData, err := json.Marshal(data)
	if err != nil {
		return
	}

	var jobId string
	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, tcId, "provision_domain_transfer_in", pdti.ID, serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)

	return
}

func getProvisionDomainTransferIn(db database.Database, id string) (pdti *model.ProvisionDomainTransferIn, err error) {
	tx := db.GetDB()

	err = tx.Where("id = ?", id).First(&pdti).Error
	return
}

func (suite *RyDomainTransferInTestSuite) TestRyDomainTransferInHandler() {
	expectedContext := context.Background()

	job, pdti, err := insertRyDomainTransferInTestJob(suite.db)
	suite.NoError(err)

	envelope := &message.TcWire{CorrelationId: job.ID}

	err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to update test job")

	suite.s.On("Context").Return(expectedContext)
	suite.s.On("Headers").Return(nil)
	suite.s.On("Envelope").Return(envelope)
	msg := &rymessages.DomainInfoResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  true,
			EppCode:    1000,
			EppMessage: "",
		},
		Hosts: []string{
			"ns1.test-domain.sexy",
			"ns2.test-domain.sexy",
		},
		CreatedDate: timestamppb.Now(),
		ExpiryDate:  timestamppb.Now(),
	}

	service := NewWorkerService(suite.mb, suite.db, suite.tracer)

	handler := service.RyDomainInfoRouter
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	updatedPdti, err := getProvisionDomainTransferIn(suite.db, pdti.ID)
	suite.NoError(err, "Failed to get updated ProvisionDomainTransferIn")

	expectedHosts := &pq.StringArray{
		"ns1.test-domain.sexy",
		"ns2.test-domain.sexy",
	}

	suite.Equal(expectedHosts, updatedPdti.Hosts)
	suite.Equal(msg.CreatedDate.AsTime().UTC().Truncate(time.Second), updatedPdti.RyCreatedDate.UTC().Truncate(time.Second))
	suite.Equal(msg.ExpiryDate.AsTime().UTC().Truncate(time.Second), updatedPdti.RyExpiryDate.UTC().Truncate(time.Second))

	suite.s.AssertExpectations(suite.T())
}

func (suite *RyDomainTransferInTestSuite) TestRyErrResponseDomainTransferInHandler() {
	expectedContext := context.Background()

	job, _, err := insertRyDomainTransferInTestJob(suite.db)
	suite.NoError(err)

	envelope := &message.TcWire{CorrelationId: job.ID}

	err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to update test job")

	suite.s.On("Context").Return(expectedContext)
	suite.s.On("Headers").Return(nil)
	suite.s.On("Envelope").Return(envelope)
	eppErrMessage := "failed to get domain info"
	msg := &rymessages.DomainInfoResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  false,
			EppCode:    types.EppCode.ObjectDoesNotExist,
			EppMessage: eppErrMessage,
		},
		Nameservers: []string{
			"ns1.test-domain.sexy",
			"ns2.test-domain.sexy",
		},
		CreatedDate: timestamppb.Now(),
		ExpiryDate:  timestamppb.Now(),
	}

	service := NewWorkerService(suite.mb, suite.db, suite.tracer)

	handler := service.RyDomainInfoRouter
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	job, err = suite.db.GetJobById(expectedContext, job.ID, false)
	suite.NoError(err, "Failed to fetch updated job")

	suite.Equal("failed", *job.Info.JobStatusName)

	suite.Equal(eppErrMessage, *job.ResultMessage)

	suite.s.AssertExpectations(suite.T())
}
