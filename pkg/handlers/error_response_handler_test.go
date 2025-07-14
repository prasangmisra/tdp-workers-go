package handlers

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message"
	config "github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

type RyContactErrorResponseTestSuite struct {
	suite.Suite
	db database.Database
	mb *mocks.MockMessageBus
	s  *mocks.MockMessageBusServer
}

func TestRyContactErrorResponseTestSuite(t *testing.T) {
	suite.Run(t, new(RyContactErrorResponseTestSuite))
}

func (suite *RyContactErrorResponseTestSuite) SetupSuite() {
	config, err := config.LoadConfiguration("../../.env")
	suite.NoError(err, "Failed to read config from .env")

	config.LogLevel = "mute" // suppress log output
	log.Setup(config)

	db, err := database.New(config.PostgresPoolConfig(), config.GetDBLogLevel())
	suite.NoError(err, types.LogMessages.DatabaseConnectionFailed)
	suite.db = db
}

func (suite *RyContactErrorResponseTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func getTestContactData() (data *types.ContactData) {
	data = &types.ContactData{
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
		ProvisionContactId: "test_provisionContactId",
		TenantCustomerId:   "test_tenantCustomerId",
		Pw:                 "test_pw",
	}

	return
}

func insertContactProvisionTestJob(db database.Database) (job *model.Job, err error) {
	tx := db.GetDB()

	data := getTestContactData()

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
	err = tx.Raw(sql, id, "provision_contact_create", "0268f162-5d83-44d2-894a-ab7578c498fb", serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	return db.GetJobById(context.Background(), jobId, false)
}

func (suite *RyContactErrorResponseTestSuite) TestRyContactErrorResponseHandler() {
	ctx := context.Background()

	job, err := insertContactProvisionTestJob(suite.db)
	suite.NoError(err, "Failed to insert test job")

	err = suite.db.SetJobStatus(ctx, job, types.JobStatus.Processing, nil)
	suite.NoError(err, "Failed to update test job")

	envelope := &message.TcWire{CorrelationId: job.ID}

	suite.s.On("Envelope").Return(envelope)
	suite.s.On("Context").Return(ctx)

	msg := &message.ErrorResponse{
		Code:    message.ErrorResponse_SERVICE_FAILURE,
		Message: "error message",
	}

	handler := ErrorResponseHandler(suite.db)
	suite.NoError(handler(suite.s, msg), "Handler returned an error")

	job, err = suite.db.GetJobById(ctx, job.ID, false)
	suite.NoError(err, "Failed to get test job")

	suite.Equal("failed", suite.db.GetJobStatusName(job.StatusID))
	suite.NoError(err, types.LogMessages.HandleMessageFailed)
}
