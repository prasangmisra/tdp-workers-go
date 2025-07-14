package handlers

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/stretchr/testify/suite"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message"
	commonmessages "github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	config "github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

type RyContactUpdateTestSuite struct {
	suite.Suite
	db database.Database
	mb *mocks.MockMessageBus
	s  *mocks.MockMessageBusServer
	t  *oteltrace.Tracer
}

func TestRyContactUpdateTestSuite(t *testing.T) {
	suite.Run(t, new(RyContactUpdateTestSuite))
}

func (suite *RyContactUpdateTestSuite) SetupSuite() {
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

func (suite *RyContactUpdateTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func getTestContactUpdateData() (data *types.ContactUpdateData) {
	data = &types.ContactUpdateData{
		Contact: types.Contact{
			Id:            "test_id",
			Fax:           types.ToPointer("test_fax"),
			FaxExt:        types.ToPointer("test_faxExt"),
			Email:         types.ToPointer("test_email"),
			Phone:         types.ToPointer("test_phone"),
			PhoneExt:      types.ToPointer("test_phoneExt"),
			Title:         types.ToPointer("test_title"),
			Country:       types.ToPointer("test_country"),
			OrgReg:        types.ToPointer("test_orgReg"),
			SalesTax:      types.ToPointer("test_orgVat"),
			OrgDuns:       types.ToPointer("test_orgDuns"),
			Language:      types.ToPointer("test_language"),
			ContactType:   "organization",
			Documentation: types.ToPointer("test_documentation"),
			ContactPostals: []types.Postal{
				{
					City:            types.ToPointer("test_city"),
					State:           types.ToPointer("test_state"),
					Address1:        types.ToPointer("test_address1"),
					Address2:        types.ToPointer("test_address2"),
					Address3:        types.ToPointer("test_address3"),
					OrgName:         types.ToPointer("test_orgName"),
					FirstName:       types.ToPointer("test_firstName"),
					LastName:        types.ToPointer("test_lastName"),
					PostalCode:      types.ToPointer("test_postalCode"),
					IsInternational: types.ToPointer(false),
				},
			},
			TenantCustomerId:   "test_tenantCustomerId",
			CustomerContactRef: "test_customerContactRef",
		},
		Accreditation: types.Accreditation{
			IsProxy:              false,
			TenantId:             "test_tenantId",
			TenantName:           "test_tenantName",
			ProviderId:           "test_providerId",
			ProviderName:         "test_providerName",
			AccreditationId:      "test_accreditationId",
			AccreditationName:    "test_accreditationName",
			ProviderInstanceId:   "test_providerInstanceId",
			ProviderInstanceName: "test_providerInstanceName",
		},
		Handle:                         "test_handle",
		TenantCustomerId:               "test_tenantCustomerId",
		ProvisionDomainContactUpdateId: "test_provisionDomainContactUpdateId",
	}

	return
}

func insertContactUpdateTestJob(db database.Database) (job *model.Job, err error) {
	tx := db.GetDB()

	data := getTestContactUpdateData()

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

	var jobParentId string
	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, id, "provision_contact_create", "0268f162-5d83-44d2-894a-ab7578c498fb", nil).Scan(&jobParentId).Error
	if err != nil {
		return
	}

	var jobId string
	sql = `SELECT job_submit(?, ?, ?, ?, ?, ?, ?)`
	err = tx.Raw(sql, id, "provision_contact_update", "0268f162-5d83-44d2-894a-ab7578c498fb", serializedData,
		jobParentId, time.Now(), false).Scan(&jobId).Error
	if err != nil {
		return
	}

	return db.GetJobById(context.Background(), jobId, false)
}

func (suite *RyContactUpdateTestSuite) TestRyContactUpdateHandler() {
	ctx := context.Background()

	job, err := insertContactUpdateTestJob(suite.db)
	suite.NoError(err, "Failed to insert test job")

	err = suite.db.SetJobStatus(ctx, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to update test job")

	envelope := &message.TcWire{CorrelationId: job.ID}

	service := NewWorkerService(suite.mb, suite.db, suite.t)

	suite.s.On("Envelope").Return(envelope)
	suite.s.On("Headers").Return(nil)
	suite.s.On("Context").Return(ctx)

	msg := &ryinterface.ContactUpdateResponse{
		RegistryResponse: &commonmessages.RegistryResponse{
			IsSuccess:  true,
			EppCode:    1000,
			EppMessage: "",
		},
	}

	err = service.RyContactUpdateHandler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)
}
