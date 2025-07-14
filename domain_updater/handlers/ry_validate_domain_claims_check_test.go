package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message"
	commonmessages "github.com/tucowsinc/tdp-messages-go/message/common"
	rymessages "github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

func TestRyValidateDomainClaimsTestSuite(t *testing.T) {
	suite.Run(t, new(RyValidateDomainClaimsTestSuite))
}

type RyValidateDomainClaimsTestSuite struct {
	suite.Suite
	db database.Database
	mb *mocks.MockMessageBus
	s  *mocks.MockMessageBusServer
	t  *oteltrace.Tracer
}

func (suite *RyValidateDomainClaimsTestSuite) SetupSuite() {
	cfg, err := config.LoadConfiguration("../../.env")
	suite.NoError(err, "Failed to read config from .env")

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
}

func (suite *RyValidateDomainClaimsTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertValidateDomainClaimsTestOrderAndJob(db database.Database, withOrderItem bool, domainName string, launchData *types.DomainLaunchData) (job *model.Job, data types.DomainClaimsValidationData, err error) {
	tx := db.GetDB()

	//get a tenant id (doesn't matter which)
	//automatically generated when db is brought up
	type TenantCustomer struct {
		Id       string `gorm:"column:id"`
		TenantId string `gorm:"column:tenant_id"`
	}
	var tenantCustomer TenantCustomer
	err = tx.Table("v_tenant_customer").Select("id", "tenant_id").Scan(&tenantCustomer).Error
	if err != nil {
		return
	}

	var orderItemCreateDomain model.OrderItemCreateDomain
	if withOrderItem {
		var orderId string
		// create test order_items
		err = tx.Raw(`
		INSERT INTO "order"
        (tenant_customer_id, type_id)
		VALUES(
			$1::UUID,
			(SELECT id FROM v_order_type WHERE product_name='domain' AND name='create'))
			RETURNING id
	`, tenantCustomer.Id).Scan(&orderId).Error
		if err != nil {
			return
		}

		err = tx.Raw(`
		INSERT INTO order_item_create_domain(
        order_id,
        name,
		launch_data
		) VALUES(
			$1::UUID,
			$2,
			jsonb_build_object('testfield1', 'testval1')
		) RETURNING *
	`, orderId, domainName).Scan(&orderItemCreateDomain).Error
		if err != nil {
			return
		}
	}
	data = types.DomainClaimsValidationData{
		Name:             domainName,
		OrderItemPlanId:  uuid.NewString(),
		TenantCustomerId: tenantCustomer.Id,
		Accreditation: types.Accreditation{
			IsProxy:           false,
			AccreditationName: accreditationName,
			TenantId:          tenantCustomer.TenantId,
		},
		LaunchData:  launchData,
		OrderItemId: orderItemCreateDomain.ID,
	}

	serializedData, _ := json.Marshal(data)

	var jobId string
	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, tenantCustomer.Id, "validate_domain_claims", data.OrderItemPlanId, serializedData).Scan(&jobId).Error

	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)

	return
}

func (suite *RyValidateDomainClaimsTestSuite) TestRyDomainValidateAvailabilityHandler() {
	expectedContext := context.Background()

	p := extension.LaunchPhase_CLAIMS

	launchData := types.DomainLaunchData{
		Claims: &types.DomainClaimsData{
			Type:   types.ToPointer("tmch"),
			Phase:  "claims",
			Notice: []types.ClaimsNotice{},
		},
	}

	testCases := []struct {
		name                string
		isSuccess           bool
		eppCode             int32
		launchCheckResponse proto.Message
		expectedJobStatus   string
		expectedJobResult   string
		launchData          *types.DomainLaunchData
		withOrderItem       bool
	}{
		{
			name:                "invalid check response",
			isSuccess:           true,
			eppCode:             1001,
			launchCheckResponse: nil,
			expectedJobStatus:   "failed",
			expectedJobResult:   "domain validation failed",
		},
		{
			name:                "failed claim check response",
			isSuccess:           false,
			eppCode:             2400,
			launchCheckResponse: nil,
			expectedJobStatus:   "failed",
			expectedJobResult:   "domain validation failed",
		},
		{
			name:                "invalid extension",
			isSuccess:           true,
			eppCode:             1000,
			launchCheckResponse: &extension.FeeCheckResponse{},
			expectedJobStatus:   "failed",
			expectedJobResult:   "domain validation failed",
		},
		{
			name:      "missing response data",
			isSuccess: true,
			eppCode:   1000,
			launchCheckResponse: &extension.LaunchCheckResponse{
				Phase: &p,
			},
			expectedJobStatus: "failed",
			expectedJobResult: "domain validation failed",
		},
		{
			name:      "required claims with missing launch data",
			isSuccess: true,
			eppCode:   1000,
			launchCheckResponse: &extension.LaunchCheckResponse{
				Phase: &p,
				Data: []*extension.LaunchCheckData{
					{
						Name:     fmt.Sprintf("test-%s.help", uuid.NewString()),
						Exists:   true,
						ClaimKey: nil,
					},
				},
			},
			expectedJobStatus: "failed",
			expectedJobResult: "claims data is missing",
		},
		{
			name:      "required claims with launch data",
			isSuccess: true,
			eppCode:   1000,
			launchCheckResponse: &extension.LaunchCheckResponse{
				Phase: &p,
				Data: []*extension.LaunchCheckData{
					{
						Name:     fmt.Sprintf("test-%s.help", uuid.NewString()),
						Exists:   true,
						ClaimKey: nil,
					},
				},
			},
			expectedJobStatus: "completed",
			expectedJobResult: "",
			launchData:        &launchData,
		},
		{
			name:      "successful check claims not required",
			isSuccess: true,
			eppCode:   1000,
			launchCheckResponse: &extension.LaunchCheckResponse{
				Phase: &p,
				Data: []*extension.LaunchCheckData{
					{
						Name:     fmt.Sprintf("test-%s.help", uuid.NewString()),
						Exists:   false,
						ClaimKey: nil,
					},
				},
			},
			expectedJobStatus: "completed",
			expectedJobResult: "",
			launchData:        &launchData,
			withOrderItem:     true,
		},
		{
			name:      "successful check claims not required order not found",
			isSuccess: true,
			eppCode:   1000,
			launchCheckResponse: &extension.LaunchCheckResponse{
				Phase: &p,
				Data: []*extension.LaunchCheckData{
					{
						Name:     fmt.Sprintf("test-%s.help", uuid.NewString()),
						Exists:   false,
						ClaimKey: nil,
					},
				},
			},
			expectedJobStatus: "failed",
			expectedJobResult: "domain validation failed",
			launchData:        &launchData,
			withOrderItem:     false,
		},
	}

	for _, tc := range testCases {
		suite.Run(tc.name, func() {

			var domainName string
			switch tc.launchCheckResponse.(type) {
			case *extension.LaunchCheckResponse:
				if tc.launchCheckResponse.(*extension.LaunchCheckResponse).Data == nil {
					domainName = fmt.Sprintf("test-%s.help", uuid.NewString())
					break
				}
				domainName = tc.launchCheckResponse.(*extension.LaunchCheckResponse).Data[0].Name
			default:
				domainName = fmt.Sprintf("test-%s.help", uuid.NewString())
			}

			job, _, err := insertValidateDomainClaimsTestOrderAndJob(suite.db, tc.withOrderItem, domainName, tc.launchData)
			suite.NoError(err, "Failed to insert test job")

			err = suite.db.SetJobStatus(expectedContext, job, types.JobStatus.Processing, nil)
			suite.NoError(err, "Failed to update test job")

			envelope := &message.TcWire{CorrelationId: job.ID}

			launchExtension, _ := anypb.New(tc.launchCheckResponse)

			msg := &rymessages.DomainCheckResponse{
				RegistryResponse: &commonmessages.RegistryResponse{
					IsSuccess: tc.isSuccess,
					EppCode:   tc.eppCode,
				},
				Extensions: map[string]*anypb.Any{"launch": launchExtension},
			}

			if tc.eppCode != types.EppCode.Success {
				msg.RegistryResponse.EppMessage = tc.expectedJobResult
			}
			service := NewWorkerService(suite.mb, suite.db, suite.t)

			suite.s = &mocks.MockMessageBusServer{}
			suite.s.On("Context").Return(expectedContext)
			suite.s.On("Headers").Return(nil)
			suite.s.On("Envelope").Return(envelope)

			handler := service.RyDomainCheckHandler
			err = handler(suite.s, msg)
			suite.NoError(err, types.LogMessages.HandleMessageFailed)

			job, err = suite.db.GetJobById(expectedContext, job.ID, false)
			suite.NoError(err, "Failed to fetch updated job")

			suite.Equal(tc.expectedJobStatus, *job.Info.JobStatusName)

			if job.ResultMessage != nil {
				suite.Equal(tc.expectedJobResult, *job.ResultMessage)
			}

			suite.s.AssertExpectations(suite.T())
		})
	}
}
