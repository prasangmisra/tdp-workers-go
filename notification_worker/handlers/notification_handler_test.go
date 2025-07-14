package handlers

import (
	"context"
	"testing"
	"time"

	"github.com/jmoiron/sqlx/types"
	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/worker"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/repository"
	"github.com/tucowsinc/tdp-workers-go/pkg/repository/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/repository/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	internalTypes "github.com/tucowsinc/tdp-workers-go/pkg/types"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type NotificationTestSuite struct {
	suite.Suite
	ctx     context.Context
	db      database.Database
	service *WorkerService
	mb      *mocks.MockMessageBus
	s       *mocks.MockMessageBusServer
	t       *oteltrace.Tracer
}

func TestNotificationSuite(t *testing.T) {
	suite.Run(t, new(NotificationTestSuite))
}

func (suite *NotificationTestSuite) SetupSuite() {
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
	suite.NoError(err, internalTypes.LogMessages.DatabaseConnectionFailed)
	suite.db = db
	suite.ctx = context.Background()
}

func (suite *NotificationTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}

	service, err := NewWorkerService(suite.mb, suite.db, suite.t)
	suite.NoError(err, "Failed to create WorkerService")
	suite.service = service
}

func (suite *NotificationTestSuite) TestNotificationHandler() {
	notificationTypeName := "domain.transfer"

	name := "example.com"
	status := "penidng"
	requestedBy := "ClientX"
	actionBy := "ClientY"

	// get test poll subscription
	var sub []*model.Subscription
	err := suite.service.db.GetDB().WithContext(suite.ctx).Table("v_subscription").Where("type = ?", "poll").Find(&sub).Error
	suite.NoError(err)
	suite.NotEmpty(sub)

	testTenantId := sub[0].TenantID
	testTenantCustomerId := sub[0].TenantCustomerID

	notificationMsg := &common.TransferNotification{
		Name:          &name,
		Status:        &status,
		RequestedBy:   &requestedBy,
		RequestedDate: timestamppb.New(time.Now()),
		ActionBy:      &actionBy,
		ActionDate:    timestamppb.New(time.Now()),
		ExpiryDate:    timestamppb.New(time.Now()),
	}

	notificationData, err := anypb.New(notificationMsg)

	suite.NoError(err)

	msg := &worker.NotificationMessage{
		Type:             notificationTypeName,
		TenantId:         testTenantId,
		TenantCustomerId: testTenantCustomerId,
		Data:             notificationData,
	}

	suite.s.On("Context").Return(suite.ctx)
	suite.s.On("Headers").Return(map[string]any{})

	err = suite.service.NotificationHandler(suite.s, msg)
	suite.NoError(err, "Failed to process notification")

	// get notification from database to compare
	notifications, err := suite.service.notificationRepo.Filter(
		suite.ctx,
		&repository.Filter[*model.Notification]{
			Model: &model.Notification{
				TypeID:   suite.service.notificationTypeLT.GetIdByName(notificationTypeName),
				TenantID: testTenantId,
			},
			OrderBy:        "created_date",
			OrderDirection: repository.OrderDirection.DESC,
			Limit:          1,
		},
	)

	suite.NoError(err)
	suite.Lenf(notifications, 1, "must be only one record returned")

	var payload types.JSONText

	payload, err = protojson.Marshal(notificationMsg)
	suite.NoError(err)

	suite.JSONEqf(notifications[0].Payload.String(), payload.String(), "payload data must be same")
	suite.mb.AssertExpectations(suite.T())
}
