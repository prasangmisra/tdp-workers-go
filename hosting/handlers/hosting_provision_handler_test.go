package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"testing"

	"golang.org/x/exp/rand"

	"github.com/google/uuid"
	"github.com/jarcoal/httpmock"
	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	jobmessage "github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-shared-go/dns"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

type HostingProvisionTestSuite struct {
	suite.Suite
	ctx     context.Context
	db      database.Database
	cfg     config.Config
	service *WorkerService
	mb      *mocks.MockMessageBus
	s       *mocks.MockMessageBusServer
}

func TestHostingProvisionSuite(t *testing.T) {
	suite.Run(t, new(HostingProvisionTestSuite))
}

func (suite *HostingProvisionTestSuite) SetupSuite() {
	cfg, err := config.LoadConfiguration("../../.env")
	suite.NoError(err, "Failed to read config from .env")

	cfg.LogLevel = "mute" // suppress log output
	log.Setup(cfg)

	db, err := database.New(cfg.PostgresPoolConfig(), cfg.GetDBLogLevel())
	suite.NoError(err, types.LogMessages.DatabaseConnectionFailed)
	suite.db = db
	suite.cfg = cfg
	suite.ctx = context.Background()
}

func (suite *HostingProvisionTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}

	resolver, _ := dns.New()
	suite.service = NewWorkerService(suite.mb, suite.db, resolver, suite.cfg)

	httpmock.Activate()
	httpmock.ActivateNonDefault(suite.service.hostingApi.client.GetClient())
}

func getHostingProvisionTestJobData() *types.HostingData {
	testName := "test-name"
	testUsername := "test-username"
	testPassword := "test-password"
	testExternalClientId := "test-external-client-id"

	return &types.HostingData{
		DomainName:   "test.com",
		CustomerName: "test-reseller-name",
		RegionId:     "test-region-id",
		ProductId:    "test-product-id",
		HostingId:    "test-hosting-id",
		Client: types.HostingClient{
			Name:             testName,
			Email:            "test@email.com",
			Username:         testUsername,
			Password:         testPassword,
			ExternalClientId: &testExternalClientId,
		},
		Certificate:      &types.HostingCertificate{},
		TenantCustomerId: "",
	}
}

func insertHostingProvisionTestJob(db database.Database, data *types.HostingData) (job *model.Job, err error) {
	tx := db.GetDB()

	serializedData, err := json.Marshal(data)
	if err != nil {
		return
	}

	var id string
	if err = tx.Table("tenant_customer").Select("id").Scan(&id).Error; err != nil {
		return
	}

	var jobId string
	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, id, "provision_hosting_create", "0268f162-5d83-44d2-894a-ab7578c498fb", serializedData).
		Scan(&jobId).Error

	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)
	return
}

func (suite *HostingProvisionTestSuite) insertProvisionHostingCreate() (*model.Job, *model.ProvisionHostingCreate) {
	suite.T().Helper()
	tx := suite.db.GetDB()

	obj := &model.ProvisionHostingCreate{
		HostingID:  uuid.NewString(),
		DomainName: fmt.Sprintf("test%d.help", rand.Int()),
	}

	err := tx.Table("tenant_customer").Select("id").
		Limit(1).Scan(&obj.TenantCustomerID).Error
	suite.NoError(err)

	err = tx.Table("hosting_product").Select("id").
		Limit(1).Scan(&obj.ProductID).Error
	suite.NoError(err)

	err = tx.Table("hosting_region").Select("id").
		Limit(1).Scan(&obj.RegionID).Error
	suite.NoError(err)

	err = tx.Table("order_item_create_hosting_client").Select("id").
		Where(`tenant_customer_id=?`, obj.TenantCustomerID).
		Limit(1).Scan(&obj.ClientID).Error
	suite.NoError(err)

	err = tx.Create(obj).Error
	suite.NoError(err)

	err = tx.Where("id = ?", obj.ID).First(obj).Error
	suite.NoError(err)

	job := &model.Job{}
	err = tx.Where("reference_id = ?", obj.ID).First(job).Error
	suite.NoError(err)

	return job, obj
}

func (suite *HostingProvisionTestSuite) getProvisionHostingCreate(id string) *model.ProvisionHostingCreate {
	suite.T().Helper()
	res := &model.ProvisionHostingCreate{}
	err := suite.db.GetDB().Where("id = ?", id).First(res).Error
	suite.NoError(err)
	return res
}

func (suite *HostingProvisionTestSuite) TestHostingProvisionHandler() {
	job, provisionHostingCreate := suite.insertProvisionHostingCreate()
	suite.Equal(types.ProvisionStatus.Pending, suite.db.GetProvisionStatusName(provisionHostingCreate.StatusID))
	suite.Equal(types.JobStatus.Submitted, suite.db.GetJobStatusName(job.StatusID))

	msg := &jobmessage.Notification{
		JobId:          job.ID,
		Type:           "hosting_provision",
		Status:         "status",
		ReferenceId:    types.SafeDeref(job.ReferenceID),
		ReferenceTable: "provision_hosting_create",
	}

	expectedOrderResponse := OrderResponse{
		Id:        uuid.NewString(),
		ClientId:  uuid.NewString(),
		Status:    "Requested",
		IsActive:  true,
		IsDeleted: false,
	}
	j, err := json.Marshal(expectedOrderResponse)
	suite.NoError(err)

	httpmock.RegisterResponder(http.MethodPost, "/orders", setupMockResponder(200, string(j)))

	expectedClientsResponse := []ClientResponse{{
		Id:       uuid.NewString(),
		Username: "test-user",
	}}
	body, err := json.Marshal(expectedClientsResponse)
	suite.NoError(err)
	httpmock.RegisterResponder(http.MethodGet, "/clients", setupMockResponder(200, string(body)))

	suite.s.On("Context").Return(suite.ctx)
	suite.s.On("Headers").Return(nil)

	err = suite.service.HostingProvisionHandler(suite.s, msg)
	suite.NoError(err)

	job, err = suite.db.GetJobById(suite.ctx, job.ID, false)

	suite.NoError(err)
	suite.Equal(types.JobStatus.CompletedConditionally, suite.db.GetJobStatusName(job.StatusID))
	suite.NotNil(job.Info.ReferenceID)

	provisionHostingCreateID := *job.Info.ReferenceID
	provisionHostingCreate = suite.getProvisionHostingCreate(provisionHostingCreateID)
	suite.NotNil(provisionHostingCreate)
	suite.Equal(types.ProvisionStatus.PendingAction, suite.db.GetProvisionStatusName(provisionHostingCreate.StatusID))
	suite.mb.AssertExpectations(suite.T())
}

func (suite *HostingProvisionTestSuite) TestHostingProvisionWithComponentsHandler() {
	data := getHostingProvisionTestJobData()

	data.Components = []types.HostingComponent{
		{Name: "test-container", Type: "container"},
		{Name: "test-database", Type: "database"},
	}

	job, err := insertHostingProvisionTestJob(suite.db, data)
	suite.NoError(err, "Failed to insert test job")

	msg := &jobmessage.Notification{
		JobId:          job.ID,
		Type:           "hosting_provision",
		Status:         "status",
		ReferenceId:    "0268f162-5d83-44d2-894a-ab7578c498fb",
		ReferenceTable: "provision_hosting_create",
	}

	expectedResponse := OrderResponse{
		Id:        uuid.NewString(),
		ClientId:  uuid.NewString(),
		Status:    "Requested",
		IsActive:  true,
		IsDeleted: false,
	}
	j, _ := json.Marshal(expectedResponse)

	httpmock.RegisterResponder(http.MethodPost, "/orders", setupMockResponder(200, string(j)))

	suite.s.On("Context").Return(suite.ctx)

	err = suite.service.HostingProvisionHandler(suite.s, msg)
	suite.NoError(err)

	job, err = suite.db.GetJobById(suite.ctx, job.ID, false)

	suite.NoError(err)
	suite.Equal(job.StatusID, suite.db.GetJobStatusId(types.JobStatus.CompletedConditionally))

	suite.mb.AssertExpectations(suite.T())
}
