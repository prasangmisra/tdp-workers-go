package handlers

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/anypb"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	rymessages "github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	config "github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

func TestValidateDomainClaimsCheckTestSuite(t *testing.T) {
	suite.Run(t, new(ValidateDomainClaimsCheckTestSuite))
}

type ValidateDomainClaimsCheckTestSuite struct {
	suite.Suite
	db     database.Database
	mb     *mocks.MockMessageBus
	s      *mocks.MockMessageBusServer
	tracer *oteltrace.Tracer
}

func (suite *ValidateDomainClaimsCheckTestSuite) SetupSuite() {
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

func (suite *ValidateDomainClaimsCheckTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertValidateDomainClaimsCheckTestJob(db database.Database) (jobId string, data types.DomainClaimsValidationData, err error) {
	tx := db.GetDB()

	//get a tenant id (doesn't matter which)
	//automatically generated when db is brought up
	var id string
	err = tx.Table("tenant_customer").Select("id").Scan(&id).Error
	if err != nil {
		return
	}

	data = types.DomainClaimsValidationData{
		Name:             "test_domain.com",
		OrderItemPlanId:  uuid.NewString(),
		TenantCustomerId: id,
		Accreditation: types.Accreditation{
			IsProxy:           false,
			AccreditationName: accreditationName,
		},
	}

	serializedData, _ := json.Marshal(data)

	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, id, "validate_domain_claims", data.OrderItemPlanId, serializedData).Scan(&jobId).Error

	return
}

func (suite *ValidateDomainClaimsCheckTestSuite) TestValidateDomainClaimsCheckHandlerHandler() {
	jobId, data, err := insertValidateDomainClaimsCheckTestJob(suite.db)
	suite.NoError(err, "Failed to insert test job")

	msg := &job.Notification{
		JobId:          jobId,
		Type:           "validate_domain_claims",
		Status:         "submitted",
		ReferenceId:    data.OrderItemPlanId,
		ReferenceTable: "order_item_plan",
	}

	expectedContext := context.Background()
	expectedDestination := types.GetQueryQueue(accreditationName)

	expectedDomainNames := []string{data.Name}

	expectedPhase := extension.LaunchPhase_CLAIMS

	launchCheckRequest := new(extension.LaunchCheckRequest)
	launchCheckRequest.Type = extension.LaunchCheckType_LCHK_CLAIMS
	launchCheckRequest.Phase = &expectedPhase
	launchExtension, err := anypb.New(launchCheckRequest)
	suite.NoError(err, "Failed to create launch extension")

	expectedMsg := rymessages.DomainCheckRequest{
		Names:      expectedDomainNames,
		Extensions: map[string]*anypb.Any{"launch": launchExtension},
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

	handler := service.ValidateDomainClaimsCheckHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}
