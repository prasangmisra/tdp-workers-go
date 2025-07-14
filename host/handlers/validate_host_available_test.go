package handlers

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/suite"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"

	rymessages "github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	config "github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

func TestValidateHostAvailableTestSuite(t *testing.T) {
	suite.Run(t, new(ValidateHostAvailableTestSuite))
}

type ValidateHostAvailableTestSuite struct {
	suite.Suite
	db database.Database
	mb *mocks.MockMessageBus
	s  *mocks.MockMessageBusServer
	t  *oteltrace.Tracer
}

func (suite *ValidateHostAvailableTestSuite) SetupSuite() {
	cfg, err := config.LoadConfiguration("../../.env")
	suite.NoError(err, "Failed to read config from .env")

	cfg.TracingEnabled = false
	tracer, _, err := tracing.Setup(context.Background(), cfg)
	if err != nil {
		log.Fatal("Error setting up tracing", log.Fields{"error": err})
	}
	suite.t = tracer

	db, err := database.New(cfg.PostgresPoolConfig(), cfg.GetDBLogLevel())
	suite.NoError(err, types.LogMessages.DatabaseConnectionFailed)
	suite.db = db
}

func (suite *ValidateHostAvailableTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertValidateHostAvailableTestJob(db database.Database) (jobId string, data types.HostValidationData, err error) {
	tx := db.GetDB()

	//get a tenant id (doesn't matter which)
	//automatically generated when db is brought up
	var id string
	err = tx.Table("tenant_customer").Select("id").Scan(&id).Error
	if err != nil {
		return
	}

	data = types.HostValidationData{
		HostName:         "ns1.testdomain.com",
		OrderItemPlanId:  uuid.New().String(),
		TenantCustomerId: id,
		Accreditation: types.Accreditation{
			IsProxy:           false,
			AccreditationName: accreditationName,
		},
	}

	serializedData, _ := json.Marshal(data)

	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, id, "validate_host_available", data.OrderItemPlanId, serializedData).Scan(&jobId).Error

	return
}

func (suite *ValidateHostAvailableTestSuite) TestValidateHostAvailableHandlerHandler() {
	jobId, data, err := insertValidateHostAvailableTestJob(suite.db)
	suite.NoError(err, "Failed to insert test job")

	msg := &job.Notification{
		JobId:          jobId,
		Type:           "validate_host_available",
		Status:         "submitted",
		ReferenceId:    data.OrderItemPlanId,
		ReferenceTable: "order_item_plan",
	}

	expectedContext := context.Background()
	expectedDestination := types.GetQueryQueue(accreditationName)
	expectedMsg := rymessages.HostCheckRequest{
		Names: []string{data.HostName},
	}

	expectedHeaders := map[string]any{
		"reply_to":       "WorkerJobHostProvisionUpdate",
		"correlation_id": jobId,
	}

	service := NewWorkerService(suite.mb, suite.db, suite.t)

	suite.mb.On("Send", expectedContext, expectedDestination, &expectedMsg, expectedHeaders).Return(nil)
	suite.s.On("MessageBus").Return(suite.mb)
	suite.s.On("Headers").Return(nil)
	suite.s.On("Context").Return(expectedContext)

	handler := service.ValidateHostAvailableHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}
