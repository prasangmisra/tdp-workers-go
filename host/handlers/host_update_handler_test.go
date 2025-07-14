package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	jobmessage "github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

func TestHostUpdateTestSuite(t *testing.T) {
	suite.Run(t, new(HostUpdateTestSuite))
}

type HostUpdateTestSuite struct {
	suite.Suite
	db database.Database
	mb *mocks.MockMessageBus
	s  *mocks.MockMessageBusServer
	t  *oteltrace.Tracer
}

func (suite *HostUpdateTestSuite) SetupSuite() {
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
}

func (suite *HostUpdateTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertTestHost(db database.Database, name string) (host *model.Host, err error) {
	tx := db.GetDB()

	test_address1 := "192.168.0.1"
	test_address2 := "192.168.0.4"
	host = &model.Host{
		ID:               uuid.NewString(),
		TenantCustomerID: "d50ff47e-2a80-4528-b455-6dc5d200ecbe",
		Name:             name,
		HostAddrs: []model.HostAddr{
			{
				HostID:  uuid.NewString(),
				Address: &test_address1,
			},
			{
				HostID:  uuid.NewString(),
				Address: &test_address2,
			},
		},
	}

	err = tx.Create(host).Error

	return
}

func insertHostUpdateTestJob(db database.Database) (job *model.Job, data *types.HostUpdateData, err error) {
	tx := db.GetDB()

	host, err := insertTestHost(db, fmt.Sprintf("ns%s.tucows.help", strings.Split(uuid.NewString(), "-")[0]))
	if err != nil {
		return
	}

	data = &types.HostUpdateData{
		HostId:   host.ID,
		HostName: host.Name,
		HostNewAddrs: []string{
			"192.168.0.10",
			"192.168.0.30",
		},
		HostOldAddrs: []string{
			"192.168.0.10",
			"192.168.0.20",
			"192.168.0.40",
		},
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
		TenantCustomerId:      host.TenantCustomerID,
		ProvisionHostUpdateId: "0268f162-5d83-44d2-894a-ab7578c498fj",
	}

	serializedData, err := json.Marshal(data)
	if err != nil {
		return
	}

	//get a tenant id (doesn't matter which)
	//automatically generated when db is brought up
	var id string
	err = tx.Table("tenant_customer").Select("id").Scan(&id).Error
	if err != nil {
		return
	}

	var jobId string
	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, id, "provision_host_update", "0268f162-5d83-44d2-894a-ab7578c498fb", serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)

	return
}

func (suite *HostUpdateTestSuite) TestHostUpdateHandler() {
	job, data, err := insertHostUpdateTestJob(suite.db)
	suite.NoError(err, "Failed to insert test job")

	expectedContext := context.Background()

	expectedDestination := types.GetTransformQueue(accreditationName)
	expectedMsg := ryinterface.HostUpdateRequest{
		Name: data.HostName,
		Add: &ryinterface.HostUpdateElement{
			Addresses: []string{
				"192.168.0.30",
			},
		},
		Rem: &ryinterface.HostUpdateElement{
			Addresses: []string{
				"192.168.0.20",
				"192.168.0.50",
			},
		},
	}

	expectedHeaders := map[string]any{
		"reply_to":       "WorkerJobHostProvisionUpdate",
		"correlation_id": job.ID,
	}

	suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), types.GetQueryQueue(accreditationName), &ryinterface.HostInfoRequest{
		Name: data.HostName,
	}, mock.Anything).Return(
		messagebus.RpcResponse{
			Server: suite.s,
			Message: &ryinterface.HostInfoResponse{
				Addresses: []string{
					"192.168.0.10",
					"192.168.0.20",
					"192.168.0.50",
				},
			},
			Err: nil,
		},
		nil,
	)
	suite.mb.On("Send", expectedContext, expectedDestination, &expectedMsg, expectedHeaders).Return(nil)
	suite.s.On("MessageBus").Return(suite.mb)
	suite.s.On("Headers").Return(expectedHeaders)
	suite.s.On("Context").Return(expectedContext)

	msg := &jobmessage.Notification{
		JobId:          job.ID,
		Type:           "provision_host_update",
		Status:         "status",
		ReferenceId:    "0268f162-5d83-44d2-894a-ab7578c498fb",
		ReferenceTable: "1234",
	}

	service := NewWorkerService(suite.mb, suite.db, suite.t)

	err = service.HostUpdateHandler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}
