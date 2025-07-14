package handlers

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	"github.com/google/uuid"
	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/sqs"
	hostingproto "github.com/tucowsinc/tucows-domainshosting-app/cmd/functions/order/proto"
	"google.golang.org/protobuf/types/known/timestamppb"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

type HostingOrderDetailsResponseTestSuite struct {
	suite.Suite
	ctx      context.Context
	db       database.Database
	cfg      config.Config
	service  *WorkerService
	consumer *sqs.MockConsumer
	s        sqs.Server
}

func TestHostingOrderDetailsResponse(t *testing.T) {
	suite.Run(t, new(HostingOrderDetailsResponseTestSuite))
}

func (suite *HostingOrderDetailsResponseTestSuite) SetupSuite() {
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

func (suite *HostingOrderDetailsResponseTestSuite) SetupTest() {
	suite.consumer = &sqs.MockConsumer{}
	suite.service = NewWorkerService(suite.consumer, suite.db)

	suite.s = sqs.Server{
		Ctx: suite.ctx,
	}
}

func insertHosting(db database.Database) (hosting *model.Hosting, err error) {
	tx := db.GetDB()

	testName := "test-name"
	testUsername := "test-username"
	testPassword := "test-password"
	testClientId := "test-client"
	testExternalOrderId := uuid.NewString()

	hosting = &model.Hosting{
		DomainName:      fmt.Sprintf("test%v.com", uuid.NewString()),
		ClientID:        testClientId,
		ExternalOrderID: &testExternalOrderId,
		Client: model.HostingClient{
			ID:       uuid.NewString(),
			Name:     &testName,
			Email:    "test@email.com",
			Username: &testUsername,
			Password: &testPassword,
		},
		Certificate: &model.HostingCertificate{
			NotBefore: timestamppb.Now().AsTime(),
			NotAfter:  timestamppb.Now().AsTime().Add(90 * 24 * time.Hour),
		},
		TenantCustomerID: "",
	}

	var id string
	if err = tx.Table("tenant_customer").Select("id").Scan(&id).Error; err != nil {
		return
	}
	hosting.TenantCustomerID = id
	hosting.Client.TenantCustomerID = id

	if err = tx.Table("hosting_region").Select("id").Scan(&id).Error; err != nil {
		return
	}
	hosting.RegionID = id

	if err = tx.Table("hosting_product").Select("id").Scan(&id).Error; err != nil {
		return
	}
	hosting.ProductID = id

	err = tx.Create(hosting).Error

	return
}

func (suite *HostingOrderDetailsResponseTestSuite) insertProvisionHostingCreate(hosting *model.Hosting) *model.ProvisionHostingCreate {
	suite.T().Helper()
	tx := suite.db.GetDB()

	obj := &model.ProvisionHostingCreate{
		HostingID:        hosting.ID,
		ExternalOrderID:  hosting.ExternalOrderID,
		DomainName:       hosting.DomainName,
		TenantCustomerID: hosting.TenantCustomerID,
		ProductID:        hosting.ProductID,
		RegionID:         hosting.RegionID,
		ClientID:         hosting.ClientID,
	}

	err := tx.Create(obj).Error
	suite.Require().NoError(err)

	// update status to pending_action to match search condition
	obj.StatusID = suite.db.GetProvisionStatusId(types.ProvisionStatus.PendingAction)
	err = tx.Updates(obj).Error
	suite.Require().NoError(err)

	err = tx.Where("id = ?", obj.ID).First(obj).Error
	suite.Require().NoError(err)

	// update corresponding job status to completed_conditionally
	job := suite.getJob(obj.ID)
	job.StatusID = suite.db.GetJobStatusId(types.JobStatus.CompletedConditionally)
	err = suite.db.UpdateJob(suite.ctx, job)
	suite.Require().NoError(err)

	return obj
}

func (suite *HostingOrderDetailsResponseTestSuite) getJob(refID string) *model.Job {
	suite.T().Helper()
	res := &model.Job{}
	err := suite.db.GetDB().Where("reference_id = ?", refID).First(res).Error
	suite.Require().NoError(err)
	return res
}

func (suite *HostingOrderDetailsResponseTestSuite) getProvisionHostingCreate(obj *model.ProvisionHostingCreate) (*model.ProvisionHostingCreate, error) {
	return obj, suite.db.GetDB().Where(obj).First(obj).Error
}

func msgFromHosting(hosting *model.Hosting, msg *hostingproto.OrderDetailsResponse) *hostingproto.OrderDetailsResponse {
	id := types.SafeDeref(hosting.ExternalOrderID)
	if msg.Id != "" {
		id = msg.Id
	}
	return &hostingproto.OrderDetailsResponse{
		Id:         id,
		ProductId:  hosting.ProductID,
		ClientId:   hosting.ClientID,
		ClientName: types.SafeDeref(hosting.Client.Name),
		DomainName: hosting.DomainName,

		Status:        msg.Status,
		IsActive:      msg.IsActive,
		IsDeleted:     msg.IsDeleted,
		StatusDetails: msg.StatusDetails,

		CreatedAt: timestamppb.Now(),
	}
}

func (suite *HostingOrderDetailsResponseTestSuite) TestOrderDetailsResponseHandler() {
	tests := []struct {
		name string
		msg  *hostingproto.OrderDetailsResponse

		expectedHosting                func(updated, old *model.Hosting, msg *hostingproto.OrderDetailsResponse)
		expectedProvisionHostingCreate func(provisionHostingCreate *model.ProvisionHostingCreate, msg *hostingproto.OrderDetailsResponse)
		prepare                        func(provision *model.ProvisionHostingCreate)
		updateExternalOrderID          func(msg *hostingproto.OrderDetailsResponse, id string) *hostingproto.OrderDetailsResponse
	}{
		{
			name: "Completed",
			msg: &hostingproto.OrderDetailsResponse{
				Status:    types.OrderStatusHostingAPI.Completed,
				IsActive:  true,
				IsDeleted: false,
			},
			expectedHosting: func(updated, old *model.Hosting, msg *hostingproto.OrderDetailsResponse) {
				suite.Require().Equal(msg.Status, suite.db.GetHostingStatusName(types.SafeDeref(updated.HostingStatusID)))
				suite.Require().Equal(msg.IsActive, updated.IsActive)
				suite.Require().Equal(msg.IsDeleted, updated.IsDeleted)
				suite.Require().Equal(msg.Id, types.SafeDeref(updated.ExternalOrderID))
			},
			expectedProvisionHostingCreate: func(old *model.ProvisionHostingCreate, msg *hostingproto.OrderDetailsResponse) {
				updated, err := suite.getProvisionHostingCreate(&model.ProvisionHostingCreate{ID: old.ID})
				suite.Require().NoError(err)
				suite.Require().Equal(msg.Status, suite.db.GetHostingStatusName(types.SafeDeref(updated.HostingStatusID)))
				suite.Require().Equal(msg.IsActive, updated.IsActive)
				suite.Require().Equal(msg.IsDeleted, updated.IsDeleted)

				suite.Require().Equal(types.ProvisionStatus.Completed, suite.db.GetProvisionStatusName(updated.StatusID))
			},
		},
		{
			name: "Failed",
			msg: &hostingproto.OrderDetailsResponse{
				Status:    types.OrderStatusHostingAPI.Failed,
				IsActive:  true,
				IsDeleted: false,
			},
			expectedHosting: func(updated, old *model.Hosting, msg *hostingproto.OrderDetailsResponse) {
				// is set to failed and is deleted by DB trigger
				suite.Require().Equal("Failed", suite.db.GetHostingStatusName(types.SafeDeref(updated.HostingStatusID)))
				suite.Require().Equal(true, updated.IsDeleted)
			},
			expectedProvisionHostingCreate: func(old *model.ProvisionHostingCreate, msg *hostingproto.OrderDetailsResponse) {
				// failed provision hosting create records are deleted by Db trigger
				_, err := suite.getProvisionHostingCreate(&model.ProvisionHostingCreate{ID: old.ID})
				suite.Require().Error(err, database.ErrNotFound)
			},
		},
		{
			name: "Invalid Status",
			msg: &hostingproto.OrderDetailsResponse{
				Status:    "invalid-status",
				IsActive:  true,
				IsDeleted: false,
			},
			expectedHosting: func(updated, old *model.Hosting, msg *hostingproto.OrderDetailsResponse) {
				// no effect on the hosting record
				suite.Require().Equal(
					suite.db.GetHostingStatusName(types.SafeDeref(old.HostingStatusID)),
					suite.db.GetHostingStatusName(types.SafeDeref(updated.HostingStatusID)),
				)
				suite.Require().Equal(old.IsActive, updated.IsActive)
				suite.Require().Equal(old.IsDeleted, updated.IsDeleted)
				suite.Require().Equal(old.ExternalOrderID, updated.ExternalOrderID)
			},
			expectedProvisionHostingCreate: func(old *model.ProvisionHostingCreate, msg *hostingproto.OrderDetailsResponse) {
				updated, err := suite.getProvisionHostingCreate(&model.ProvisionHostingCreate{ID: old.ID})
				suite.Require().NoError(err)
				suite.Require().Equal(
					suite.db.GetHostingStatusName(types.SafeDeref(old.HostingStatusID)),
					suite.db.GetHostingStatusName(types.SafeDeref(updated.HostingStatusID)),
					"Hosting status should not be updated",
				)
				suite.Require().Equal(msg.IsActive, updated.IsActive)
				suite.Require().Equal(msg.IsDeleted, updated.IsDeleted)

				// provision hosting create record status_id is not updated
				suite.Require().Equal(suite.db.GetProvisionStatusName(old.StatusID), suite.db.GetProvisionStatusName(updated.StatusID))

			},
		},
		{
			name: "NotFound",
			msg: &hostingproto.OrderDetailsResponse{
				Id:        uuid.NewString(), // custom id
				Status:    types.OrderStatusHostingAPI.Completed,
				IsActive:  true,
				IsDeleted: false,
			},
			expectedHosting: func(updated, old *model.Hosting, msg *hostingproto.OrderDetailsResponse) {
				// no effect on the hosting record
				suite.Require().Equal(
					suite.db.GetHostingStatusName(types.SafeDeref(old.HostingStatusID)),
					suite.db.GetHostingStatusName(types.SafeDeref(updated.HostingStatusID)),
				)
				suite.Require().Equal(old.IsActive, updated.IsActive)
				suite.Require().Equal(old.IsDeleted, updated.IsDeleted)
				suite.Require().Equal(old.ExternalOrderID, updated.ExternalOrderID)
			},
			expectedProvisionHostingCreate: func(old *model.ProvisionHostingCreate, msg *hostingproto.OrderDetailsResponse) {
				// no effect on the provision hosting create record
				updated, err := suite.getProvisionHostingCreate(&model.ProvisionHostingCreate{ID: old.ID})
				suite.Require().NoError(err)
				suite.Require().Equal(suite.db.GetProvisionStatusName(old.StatusID), suite.db.GetProvisionStatusName(updated.StatusID))
				suite.Require().Equal(
					suite.db.GetHostingStatusName(types.SafeDeref(old.HostingStatusID)),
					suite.db.GetHostingStatusName(types.SafeDeref(updated.HostingStatusID)),
				)
				suite.Require().Equal(old.IsActive, updated.IsActive)
				suite.Require().Equal(old.IsDeleted, updated.IsDeleted)
			},
		},
		{
			name: "ProvisionHostingCreate NotFound so Hosting Updated",
			msg: &hostingproto.OrderDetailsResponse{
				Status:        types.OrderStatusHostingAPI.Completed,
				IsActive:      true,
				IsDeleted:     false,
				StatusDetails: "example status reason",
			},
			updateExternalOrderID: func(msg *hostingproto.OrderDetailsResponse, id string) *hostingproto.OrderDetailsResponse {
				// update the external order id to match the hosting record
				msg.Id = id
				return msg
			},
			expectedHosting: func(updated, old *model.Hosting, msg *hostingproto.OrderDetailsResponse) {

				suite.Require().Equal(updated.IsActive, msg.IsActive)
				suite.Require().Equal(updated.IsDeleted, msg.IsDeleted)
				suite.Require().Equal(types.SafeDeref(updated.StatusReason), msg.StatusDetails)
			},
			prepare: func(provision *model.ProvisionHostingCreate) {
				err := suite.db.GetDB().Where("id = ?", provision.ID).Delete(&model.ProvisionHostingCreate{}).Error
				suite.Require().NoError(err)
			},
			expectedProvisionHostingCreate: func(provision *model.ProvisionHostingCreate, msg *hostingproto.OrderDetailsResponse) {
			},
		},
	}

	for _, tt := range tests {
		tt := tt
		suite.Run(tt.name, func() {
			hosting, err := insertHosting(suite.db)
			suite.Require().NoError(err, "Failed to insert test job")

			provisionHostingCreate := suite.insertProvisionHostingCreate(hosting)
			testMessage := tt.msg
			if tt.updateExternalOrderID != nil {
				testMessage = tt.updateExternalOrderID(testMessage, types.SafeDeref(hosting.ExternalOrderID))
			}
			msg := msgFromHosting(hosting, testMessage)
			if tt.prepare != nil {
				tt.prepare(provisionHostingCreate)
			}
			err = suite.service.HostingOrderDetailsResponseHandler(suite.s, msg)
			suite.Require().NoError(err)

			updatedHosting, err := suite.db.GetHosting(suite.ctx, &model.Hosting{ExternalOrderID: hosting.ExternalOrderID})
			suite.Require().NoError(err)

			tt.expectedHosting(updatedHosting, hosting, msg)
			tt.expectedProvisionHostingCreate(provisionHostingCreate, msg)
		})
	}
}
