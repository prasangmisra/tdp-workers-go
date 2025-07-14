package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/anypb"

	messagebus "github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message/common"
	jobmessage "github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	tcwire "github.com/tucowsinc/tdp-messages-go/message"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

func TestDomainUpdateTestSuite(t *testing.T) {
	suite.Run(t, new(DomainUpdateTestSuite))
}

type DomainUpdateTestSuite struct {
	suite.Suite
	db     database.Database
	mb     *mocks.MockMessageBus
	s      *mocks.MockMessageBusServer
	tracer *oteltrace.Tracer
}

func (suite *DomainUpdateTestSuite) SetupSuite() {
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

func (suite *DomainUpdateTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertTestDomainForUpdate(db database.Database, name string) (domain *model.Domain, err error) {
	tx := db.GetDB()

	var tenantCustomerID string
	err = tx.Table("tenant_customer").Select("id").Scan(&tenantCustomerID).Error
	if err != nil {
		return
	}

	var accreditationTldID *string
	err = tx.Table("accreditation_tld").Select("id").Scan(&accreditationTldID).Error
	if err != nil {
		return
	}

	createdDate := time.Now()
	expiryDate := createdDate.AddDate(1, 0, 0)

	domain = &model.Domain{
		Name:               name,
		TenantCustomerID:   tenantCustomerID,
		AccreditationTldID: accreditationTldID,
		RyCreatedDate:      createdDate,
		RyExpiryDate:       expiryDate,
		ExpiryDate:         expiryDate,
	}

	err = tx.Create(domain).Error
	if err != nil {
		return
	}

	// update contact must have real contact id
	var contactId string
	sql := `insert into contact (type_id, country) values (tc_id_from_name('contact_type', 'individual'), 'CA') returning id`
	err = tx.Raw(sql).Scan(&contactId).Error
	if err != nil {
		return
	}

	domain.DomainContacts = []model.DomainContact{
		{
			DomainID:            domain.ID,
			ContactID:           contactId,
			DomainContactTypeID: db.GetDomainContactTypeId("admin"),
			Handle:              "admin-handle-to-rem",
		},
	}

	err = tx.Create(domain.DomainContacts).Error

	return
}

func insertTestDomainForUpdateWithoutHandle(db database.Database, name string) (domain *model.Domain, err error) {
	tx := db.GetDB()

	var tenantCustomerID string
	err = tx.Table("tenant_customer").Select("id").Scan(&tenantCustomerID).Error
	if err != nil {
		return
	}

	var accreditationTldID *string
	err = tx.Table("accreditation_tld").Select("id").Scan(&accreditationTldID).Error
	if err != nil {
		return
	}

	createdDate := time.Now()
	expiryDate := createdDate.AddDate(1, 0, 0)

	domain = &model.Domain{
		Name:               name,
		TenantCustomerID:   tenantCustomerID,
		AccreditationTldID: accreditationTldID,
		RyCreatedDate:      createdDate,
		RyExpiryDate:       expiryDate,
		ExpiryDate:         expiryDate,
	}

	err = tx.Create(domain).Error
	if err != nil {
		return
	}

	// update contact must have real contact id
	var contactId string
	sql := `insert into contact (type_id, country) values (tc_id_from_name('contact_type', 'individual'), 'CA') returning id`
	err = tx.Raw(sql).Scan(&contactId).Error
	if err != nil {
		return
	}

	domain.DomainContacts = []model.DomainContact{
		{
			DomainID:            domain.ID,
			ContactID:           contactId,
			DomainContactTypeID: db.GetDomainContactTypeId("admin"),
		},
	}

	err = tx.Create(domain.DomainContacts).Error

	return
}

func insertDomainUpdateTestJob(db database.Database, domain *model.Domain, includeContact, newContactSchema, includeSecDNS bool, locks map[string]bool) (job *model.Job, data *types.DomainUpdateData, err error) {
	tx := db.GetDB()

	var id string
	err = tx.Table("tenant_customer").Select("id").Scan(&id).Error
	if err != nil {
		return
	}

	data = &types.DomainUpdateData{
		Name:             domain.Name,
		TenantCustomerId: id,
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
		AccreditationTld: types.AccreditationTld{
			AccreditationTldId: *domain.AccreditationTldID,
		},
		Locks: locks,
	}

	if includeContact {
		if !newContactSchema {
			data.Contacts = &types.DomainUpdateContactData{
				All: []types.DomainContact{
					{
						Type:   "registrant",
						Handle: "reg-handle-to-add",
					},
					{
						Type:   "admin",
						Handle: "admin-handle-to-add",
					},
				},
			}
		} else {
			data.Contacts = &types.DomainUpdateContactData{
				Add: []types.DomainContact{
					{
						Type:   "registrant",
						Handle: "reg-handle-to-add",
					},
					{
						Type:   "admin",
						Handle: "admin-handle-to-add",
					},
				},
				Rem: []types.DomainContact{
					{
						Type:   "admin",
						Handle: "admin-handle-to-rem",
					},
				},
			}
		}
	}

	if includeSecDNS {
		msl := 5
		data.SecDNSData = &types.SecDNSUpdateData{
			AddData: &types.SecDNSUpdateAddData{
				DSData: &[]types.DSData{
					{
						KeyTag:     1,
						Algorithm:  3,
						DigestType: 1,
						Digest:     "new-digest",
					},
				},
			},
			RemData: &types.SecDNSUpdateRemData{
				DSData: &[]types.DSData{
					{
						KeyTag:     1,
						Algorithm:  3,
						DigestType: 1,
						Digest:     "old-digest",
					},
				},
			},
			MaxSigLife: &msl,
		}
	}

	serializedData, err := json.Marshal(data)
	if err != nil {
		return
	}

	var jobId string
	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, id, "provision_domain_update", "0268f162-5d83-44d2-894a-ab7578c498fb", serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)

	return
}

func insertDomainUpdateTestJobNoHandle(db database.Database, domain *model.Domain, includeContact, newContactSchema bool) (job *model.Job, data *types.DomainUpdateData, err error) {
	tx := db.GetDB()

	var id string
	err = tx.Table("tenant_customer").Select("id").Scan(&id).Error
	if err != nil {
		return
	}

	data = &types.DomainUpdateData{
		Name:             domain.Name,
		TenantCustomerId: id,
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
		AccreditationTld: types.AccreditationTld{
			AccreditationTldId: *domain.AccreditationTldID,
		},
	}

	if includeContact {
		if !newContactSchema {
			data.Contacts = &types.DomainUpdateContactData{
				All: []types.DomainContact{
					{
						Type:   "registrant",
						Handle: "reg-handle-to-add",
					},
					{
						Type:   "admin",
						Handle: "admin-handle-to-add",
					},
				},
			}
		} else {
			data.Contacts = &types.DomainUpdateContactData{
				Add: []types.DomainContact{
					{
						Type:   "registrant",
						Handle: "reg-handle-to-add",
					},
					{
						Type:   "admin",
						Handle: "admin-handle-to-add",
					},
				},
				Rem: []types.DomainContact{
					{
						Type:   "admin",
						Handle: "",
					},
				},
			}
		}
	}

	serializedData, err := json.Marshal(data)
	if err != nil {
		return
	}

	var jobId string
	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, id, "provision_domain_update", "0268f162-5d83-44d2-894a-ab7578c498fb", serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)

	return
}

func insertDomainUpdateTestJobWithNameservers(db database.Database, domain *model.Domain, nsAdd, nsRem []*types.Nameserver, includeContact bool) (job *model.Job, data *types.DomainUpdateData, err error) {
	tx := db.GetDB()

	var id string
	err = tx.Table("tenant_customer").Select("id").Scan(&id).Error
	if err != nil {
		return
	}

	data = &types.DomainUpdateData{
		Name:             domain.Name,
		TenantCustomerId: id,
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
		AccreditationTld: types.AccreditationTld{
			AccreditationTldId: *domain.AccreditationTldID,
		},
	}

	if includeContact {
		data.Contacts = &types.DomainUpdateContactData{
			All: []types.DomainContact{
				{
					Type:   "admin",
					Handle: "admin-handle-to-add",
				},
			},
		}
	}

	data.Nameservers.Add = nsAdd
	data.Nameservers.Rem = nsRem

	serializedData, err := json.Marshal(data)
	if err != nil {
		return
	}

	var jobId string
	sql := `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, id, "provision_domain_update", "0268f162-5d83-44d2-894a-ab7578c498fb", serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)

	return
}

func (suite *DomainUpdateTestSuite) TestDomainUpdateHandlerWithContacts() {
	registrant := "reg-handle-to-add"

	// Test cases for different contact schemas
	testCases := []struct {
		name             string
		newContactSchema bool
	}{
		{
			name:             "with new contact schema (All field)",
			newContactSchema: false,
		},
		{
			name:             "with old contact schema (Add/Rem fields)",
			newContactSchema: true,
		},
	}

	for _, tc := range testCases {
		suite.Run(tc.name, func() {
			domainName := fmt.Sprintf("%v.sexy", uuid.NewString())

			domain, err := insertTestDomainForUpdate(suite.db, domainName)
			suite.NoError(err, "Failed to insert test domain")

			job, data, err := insertDomainUpdateTestJob(suite.db, domain, true, tc.newContactSchema, false, nil)
			suite.NoError(err, "Failed to insert test job")

			msg := &jobmessage.Notification{
				JobId:          job.ID,
				Type:           "domain_renew",
				Status:         "status",
				ReferenceId:    "0268f162-5d83-44d2-894a-ab7578c498fb",
				ReferenceTable: "1234",
			}

			expectedContext := context.Background()
			expectedDestination := types.GetTransformQueue(accreditationName)
			expectedMsg := ryinterface.DomainUpdateRequest{
				Name: data.Name,
				Add: &ryinterface.DomainAddRemBlock{
					Contacts: []*common.DomainContact{
						{
							Type: common.DomainContact_ADMIN,
							Id:   "admin-handle-to-add",
						},
					},
				},
				Rem: &ryinterface.DomainAddRemBlock{
					Contacts: []*common.DomainContact{
						{
							Type: common.DomainContact_ADMIN,
							Id:   "admin-handle-to-rem",
						},
					},
				},
				Chg: &ryinterface.DomainChgBlock{
					Registrant: &registrant,
				},
			}
			expectedHeaders := map[string]any{
				"reply_to":       "WorkerJobDomainProvisionUpdate",
				"correlation_id": job.ID,
			}

			service := NewWorkerService(suite.mb, suite.db, suite.tracer)

			suite.mb.On("Send", expectedContext, expectedDestination, &expectedMsg, expectedHeaders).Return(nil)
			suite.s.On("MessageBus").Return(suite.mb)
			suite.s.On("Headers").Return(expectedHeaders)
			suite.s.On("Context").Return(expectedContext)

			handler := service.DomainUpdateHandler
			err = handler(suite.s, msg)
			suite.NoError(err, types.LogMessages.HandleMessageFailed)

			suite.mb.AssertExpectations(suite.T())
			suite.s.AssertExpectations(suite.T())

			// Reset mock for next test case
			suite.SetupTest()
		})
	}
}

func (suite *DomainUpdateTestSuite) TestDomainUpdateHandlerWithContactsNoHandleFound() {
	domainName := fmt.Sprintf("%v.sexy", uuid.NewString())

	domain, err := insertTestDomainForUpdateWithoutHandle(suite.db, domainName)
	suite.NoError(err, "Failed to insert test domain")

	domainInfoRequest := ryinterface.DomainInfoRequest{
		Name: domainName,
	}

	registrantHandle := "reg-handle-to-add"

	expectedContext := context.Background()

	tests := []struct {
		name      string
		mockFunc  func(suite *DomainUpdateTestSuite, jobId string)
		jobStatus string
	}{
		{
			name: "Test with no handle; domain info response has handle",
			mockFunc: func(suite *DomainUpdateTestSuite, jobId string) {
				expectedHeaders := map[string]any{
					"reply_to":       "WorkerJobDomainProvisionUpdate",
					"correlation_id": jobId,
				}

				domainInfoResponse := &ryinterface.DomainInfoResponse{
					Name: domainName,
					Contacts: []*common.DomainContact{
						{
							Type: common.DomainContact_ADMIN,
							Id:   "admin-handle-to-rem",
						},
					},
				}

				domainUpdateRequest := &ryinterface.DomainUpdateRequest{
					Name: domainName,
					Chg: &ryinterface.DomainChgBlock{
						Registrant: &registrantHandle,
					},
					Add: &ryinterface.DomainAddRemBlock{
						Contacts: []*common.DomainContact{
							{
								Type: common.DomainContact_ADMIN,
								Id:   "admin-handle-to-add",
							},
						},
					},
					Rem: &ryinterface.DomainAddRemBlock{
						Contacts: []*common.DomainContact{
							{
								Type: common.DomainContact_ADMIN,
								Id:   "admin-handle-to-rem",
							},
						},
					},
				}

				suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), types.GetQueryQueue(accreditationName), &domainInfoRequest, mock.Anything).Return(
					messagebus.RpcResponse{
						Server:  suite.s,
						Message: domainInfoResponse,
						Err:     nil,
					},
					nil,
				)

				suite.mb.On("Send", expectedContext, types.GetTransformQueue(accreditationName), domainUpdateRequest, expectedHeaders).Return(nil)
				suite.s.On("MessageBus").Return(suite.mb)
				suite.s.On("Headers").Return(expectedHeaders)
				suite.s.On("Context").Return(expectedContext)
			},
			jobStatus: "processing",
		},
		{
			name: "Test with no handle; domain info response has no handle",
			mockFunc: func(suite *DomainUpdateTestSuite, jobId string) {
				expectedHeaders := map[string]any{
					"reply_to":       "WorkerJobDomainProvisionUpdate",
					"correlation_id": jobId,
				}

				domainInfoResponse := &ryinterface.DomainInfoResponse{
					Name:     domainName,
					Contacts: []*common.DomainContact{},
				}

				domainUpdateRequest := &ryinterface.DomainUpdateRequest{
					Name: domainName,
					Chg: &ryinterface.DomainChgBlock{
						Registrant: &registrantHandle,
					},
					Add: &ryinterface.DomainAddRemBlock{
						Contacts: []*common.DomainContact{
							{
								Type: common.DomainContact_ADMIN,
								Id:   "admin-handle-to-add",
							},
						},
					},
					Rem: &ryinterface.DomainAddRemBlock{},
				}

				suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), types.GetQueryQueue(accreditationName), &domainInfoRequest, mock.Anything).Return(
					messagebus.RpcResponse{
						Server:  suite.s,
						Message: domainInfoResponse,
						Err:     nil,
					},
					nil,
				)

				suite.mb.On("Send", expectedContext, types.GetTransformQueue(accreditationName), domainUpdateRequest, expectedHeaders).Return(nil)
				suite.s.On("MessageBus").Return(suite.mb)
				suite.s.On("Headers").Return(expectedHeaders)
				suite.s.On("Context").Return(expectedContext)
			},
			jobStatus: "processing",
		},
		{
			name: "Test with no handle; domain info response no handle for given type",
			mockFunc: func(suite *DomainUpdateTestSuite, jobId string) {
				expectedHeaders := map[string]any{
					"reply_to":       "WorkerJobDomainProvisionUpdate",
					"correlation_id": jobId,
				}

				domainInfoResponse := &ryinterface.DomainInfoResponse{
					Name: domainName,
					Contacts: []*common.DomainContact{
						{
							Type: common.DomainContact_TECH,
							Id:   "tech-handle",
						},
					},
				}

				domainUpdateRequest := &ryinterface.DomainUpdateRequest{
					Name: domainName,
					Chg: &ryinterface.DomainChgBlock{
						Registrant: &registrantHandle,
					},
					Add: &ryinterface.DomainAddRemBlock{
						Contacts: []*common.DomainContact{
							{
								Type: common.DomainContact_ADMIN,
								Id:   "admin-handle-to-add",
							},
						},
					},
					Rem: &ryinterface.DomainAddRemBlock{},
				}

				suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), types.GetQueryQueue(accreditationName), &domainInfoRequest, mock.Anything).Return(
					messagebus.RpcResponse{
						Server:  suite.s,
						Message: domainInfoResponse,
						Err:     nil,
					},
					nil,
				)

				suite.mb.On("Send", expectedContext, types.GetTransformQueue(accreditationName), domainUpdateRequest, expectedHeaders).Return(nil)
				suite.s.On("MessageBus").Return(suite.mb)
				suite.s.On("Headers").Return(expectedHeaders)
				suite.s.On("Context").Return(expectedContext)
			},
			jobStatus: "processing",
		},
		{
			name: "Test with no handle; domain info failed",
			mockFunc: func(suite *DomainUpdateTestSuite, jobId string) {
				expectedHeaders := map[string]any{
					"reply_to":       "WorkerJobDomainProvisionUpdate",
					"correlation_id": jobId,
				}

				domainInfoResponse := &tcwire.ErrorResponse{
					Code:    tcwire.ErrorResponse_SERVICE_FAILURE,
					Message: "Domain info failed",
				}

				suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), types.GetQueryQueue(accreditationName), &domainInfoRequest, mock.Anything).Return(
					messagebus.RpcResponse{
						Server:  suite.s,
						Message: domainInfoResponse,
						Err:     nil,
					},
					nil,
				)

				suite.s.On("Headers").Return(expectedHeaders)
				suite.s.On("Context").Return(expectedContext)
			},
			jobStatus: "failed",
		},
		{
			name: "Test with no handle; Call failed",
			mockFunc: func(suite *DomainUpdateTestSuite, jobId string) {
				expectedHeaders := map[string]any{
					"reply_to":       "WorkerJobDomainProvisionUpdate",
					"correlation_id": jobId,
				}

				suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), types.GetQueryQueue(accreditationName), &domainInfoRequest, mock.Anything).Return(
					messagebus.RpcResponse{
						Server:  suite.s,
						Message: nil,
						Err:     errors.New("call failed"),
					},
					nil,
				)

				suite.s.On("Headers").Return(expectedHeaders)
				suite.s.On("Context").Return(expectedContext)
			},
			jobStatus: "failed",
		},
	}

	for _, tc := range tests {
		for _, newContactSchema := range []bool{true} {
			suite.Run(fmt.Sprintf("%v newContactSchema: %v", tc.name, newContactSchema), func() {
				suite.SetupTest()

				service := NewWorkerService(suite.mb, suite.db, suite.tracer)

				job, _, err := insertDomainUpdateTestJobNoHandle(suite.db, domain, true, newContactSchema)
				suite.NoError(err, "Failed to insert test job")

				msg := &jobmessage.Notification{
					JobId:          job.ID,
					Type:           "domain_update",
					Status:         "status",
					ReferenceId:    "0268f162-5d83-44d2-894a-ab7578c498fb",
					ReferenceTable: "1234",
				}

				tc.mockFunc(suite, job.ID)

				handler := service.DomainUpdateHandler
				err = handler(suite.s, msg)
				suite.NoError(err, types.LogMessages.HandleMessageFailed)

				job, err = suite.db.GetJobById(expectedContext, job.ID, false)
				suite.NoError(err, "Failed to get job by id")
				suite.Equal(tc.jobStatus, *job.Info.JobStatusName)

				suite.mb.AssertExpectations(suite.T())
				suite.s.AssertExpectations(suite.T())
			})
		}
	}
}

func (suite *DomainUpdateTestSuite) TestDomainUpdateHandlerWithNameservers() {
	domainName := fmt.Sprintf("%v.sexy", uuid.NewString())

	domain, err := insertTestDomainForUpdate(suite.db, domainName)
	suite.NoError(err, "Failed to insert test domain")

	domainInfoRequest := ryinterface.DomainInfoRequest{
		Name: domainName,
	}

	expectedContext := context.Background()

	tests := []struct {
		name      string
		nsAdd     []string
		nsRem     []string
		mockFunc  func(suite *DomainUpdateTestSuite, jobId string)
		jobStatus string
	}{
		{
			name:  "Test with nameservers add/rem adjusted #1",
			nsAdd: []string{"ns1.test.com", "ns2.test.com"},
			nsRem: []string{"ns3.test.com", "ns4.test.com"},
			mockFunc: func(suite *DomainUpdateTestSuite, jobId string) {
				expectedHeaders := map[string]any{
					"reply_to":       "WorkerJobDomainProvisionUpdate",
					"correlation_id": jobId,
				}

				domainInfoResponse := &ryinterface.DomainInfoResponse{
					Name:        domainName,
					Contacts:    []*common.DomainContact{},
					Nameservers: []string{"ns1.test.com", "ns3.test.com"},
				}

				domainUpdateRequest := &ryinterface.DomainUpdateRequest{
					Name: domainName,
					Add: &ryinterface.DomainAddRemBlock{
						Nameservers: []string{"ns2.test.com"},
					},
					Rem: &ryinterface.DomainAddRemBlock{
						Nameservers: []string{"ns3.test.com"},
					},
				}

				suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), types.GetQueryQueue(accreditationName), &domainInfoRequest, mock.Anything).Return(
					messagebus.RpcResponse{
						Server:  suite.s,
						Message: domainInfoResponse,
						Err:     nil,
					},
					nil,
				)

				suite.mb.On("Send", expectedContext, types.GetTransformQueue(accreditationName), domainUpdateRequest, expectedHeaders).Return(nil)
				suite.s.On("MessageBus").Return(suite.mb)
				suite.s.On("Headers").Return(expectedHeaders)
				suite.s.On("Context").Return(expectedContext)
			},
			jobStatus: "processing",
		},
		{
			name:  "Test with nameservers add/rem adjusted #2",
			nsAdd: []string{"ns1.test.com", "ns2.test.com"},
			nsRem: []string{"ns3.test.com", "ns4.test.com"},
			mockFunc: func(suite *DomainUpdateTestSuite, jobId string) {
				expectedHeaders := map[string]any{
					"reply_to":       "WorkerJobDomainProvisionUpdate",
					"correlation_id": jobId,
				}

				domainInfoResponse := &ryinterface.DomainInfoResponse{
					Name:        domainName,
					Contacts:    []*common.DomainContact{},
					Nameservers: []string{},
				}

				domainUpdateRequest := &ryinterface.DomainUpdateRequest{
					Name: domainName,
					Add: &ryinterface.DomainAddRemBlock{
						Nameservers: []string{"ns1.test.com", "ns2.test.com"},
					},
					Rem: &ryinterface.DomainAddRemBlock{},
				}

				suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), types.GetQueryQueue(accreditationName), &domainInfoRequest, mock.Anything).Return(
					messagebus.RpcResponse{
						Server:  suite.s,
						Message: domainInfoResponse,
						Err:     nil,
					},
					nil,
				)

				suite.mb.On("Send", expectedContext, types.GetTransformQueue(accreditationName), domainUpdateRequest, expectedHeaders).Return(nil)
				suite.s.On("MessageBus").Return(suite.mb)
				suite.s.On("Headers").Return(expectedHeaders)
				suite.s.On("Context").Return(expectedContext)
			},
			jobStatus: "processing",
		},
		{
			name:  "Test with nameservers add/rem adjusted #3",
			nsAdd: []string{"ns1.test.com", "ns2.test.com"},
			nsRem: []string{"ns3.test.com", "ns4.test.com"},
			mockFunc: func(suite *DomainUpdateTestSuite, jobId string) {
				expectedHeaders := map[string]any{
					"reply_to":       "WorkerJobDomainProvisionUpdate",
					"correlation_id": jobId,
				}

				domainInfoResponse := &ryinterface.DomainInfoResponse{
					Name:        domainName,
					Contacts:    []*common.DomainContact{},
					Nameservers: []string{"ns1.test.com", "ns2.test.com", "ns3.test.com", "ns4.test.com"},
				}

				domainUpdateRequest := &ryinterface.DomainUpdateRequest{
					Name: domainName,
					Add:  &ryinterface.DomainAddRemBlock{},
					Rem: &ryinterface.DomainAddRemBlock{
						Nameservers: []string{"ns3.test.com", "ns4.test.com"},
					},
				}

				suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), types.GetQueryQueue(accreditationName), &domainInfoRequest, mock.Anything).Return(
					messagebus.RpcResponse{
						Server:  suite.s,
						Message: domainInfoResponse,
						Err:     nil,
					},
					nil,
				)

				suite.mb.On("Send", expectedContext, types.GetTransformQueue(accreditationName), domainUpdateRequest, expectedHeaders).Return(nil)
				suite.s.On("MessageBus").Return(suite.mb)
				suite.s.On("Headers").Return(expectedHeaders)
				suite.s.On("Context").Return(expectedContext)
			},
			jobStatus: "processing",
		},
		{
			name:  "Test with nameservers add/rem adjusted #4",
			nsAdd: []string{},
			nsRem: []string{"ns4.test.com"},
			mockFunc: func(suite *DomainUpdateTestSuite, jobId string) {
				expectedHeaders := map[string]any{
					"reply_to":       "WorkerJobDomainProvisionUpdate",
					"correlation_id": jobId,
				}

				domainInfoResponse := &ryinterface.DomainInfoResponse{
					Name:        domainName,
					Contacts:    []*common.DomainContact{},
					Nameservers: []string{"ns5.test.com"},
				}

				domainUpdateRequest := &ryinterface.DomainUpdateRequest{
					Name: domainName,
					Rem:  &ryinterface.DomainAddRemBlock{},
				}

				suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), types.GetQueryQueue(accreditationName), &domainInfoRequest, mock.Anything).Return(
					messagebus.RpcResponse{
						Server:  suite.s,
						Message: domainInfoResponse,
						Err:     nil,
					},
					nil,
				)

				suite.mb.On("Send", expectedContext, types.GetTransformQueue(accreditationName), domainUpdateRequest, expectedHeaders).Return(nil)
				suite.s.On("MessageBus").Return(suite.mb)
				suite.s.On("Headers").Return(expectedHeaders)
				suite.s.On("Context").Return(expectedContext)
			},
			jobStatus: "processing",
		},
		{
			name:  "Test with nameservers add/rem adjusted #5",
			nsAdd: []string{},
			nsRem: []string{},
			mockFunc: func(suite *DomainUpdateTestSuite, jobId string) {
				// When there are no changes to make, no message should be sent
				// and the job should be marked as completed directly
				suite.s.On("Headers").Return(map[string]any{})
				suite.s.On("Context").Return(expectedContext)
			},
			jobStatus: "completed",
		},
		{
			name:  "Test domain info failed",
			nsAdd: []string{},
			nsRem: []string{"ns4.test.com"},
			mockFunc: func(suite *DomainUpdateTestSuite, jobId string) {
				expectedHeaders := map[string]any{
					"reply_to":       "WorkerJobDomainProvisionUpdate",
					"correlation_id": jobId,
				}

				domainInfoResponse := &tcwire.ErrorResponse{
					Code:    tcwire.ErrorResponse_SERVICE_FAILURE,
					Message: "Domain info failed",
				}

				suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), types.GetQueryQueue(accreditationName), &domainInfoRequest, mock.Anything).Return(
					messagebus.RpcResponse{
						Server:  suite.s,
						Message: domainInfoResponse,
						Err:     nil,
					},
					nil,
				)

				suite.s.On("Headers").Return(expectedHeaders)
				suite.s.On("Context").Return(expectedContext)
			},
			jobStatus: "failed",
		},
		{
			name:  "Test Call failed",
			nsAdd: []string{},
			nsRem: []string{"ns4.test.com"},
			mockFunc: func(suite *DomainUpdateTestSuite, jobId string) {
				expectedHeaders := map[string]any{
					"reply_to":       "WorkerJobDomainProvisionUpdate",
					"correlation_id": jobId,
				}

				suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), types.GetQueryQueue(accreditationName), &domainInfoRequest, mock.Anything).Return(
					messagebus.RpcResponse{
						Server:  suite.s,
						Message: nil,
						Err:     errors.New("call failed"),
					},
					nil,
				)

				suite.s.On("Headers").Return(expectedHeaders)
				suite.s.On("Context").Return(expectedContext)
			},
			jobStatus: "failed",
		},
	}

	for _, tt := range tests {
		suite.Run(tt.name, func() {
			suite.SetupTest()

			service := NewWorkerService(suite.mb, suite.db, suite.tracer)

			nsAdd := make([]*types.Nameserver, len(tt.nsAdd))
			for i, ns := range tt.nsAdd {
				nsAdd[i] = &types.Nameserver{Name: ns}
			}

			nsRem := make([]*types.Nameserver, len(tt.nsRem))
			for i, ns := range tt.nsRem {
				nsRem[i] = &types.Nameserver{Name: ns}
			}

			job, _, err := insertDomainUpdateTestJobWithNameservers(suite.db, domain, nsAdd, nsRem, false)
			suite.NoError(err, "Failed to insert test job")

			msg := &jobmessage.Notification{
				JobId:          job.ID,
				Type:           "domain_update",
				Status:         "status",
				ReferenceId:    "0268f162-5d83-44d2-894a-ab7578c498fb",
				ReferenceTable: "1234",
			}

			tt.mockFunc(suite, job.ID)

			handler := service.DomainUpdateHandler
			err = handler(suite.s, msg)
			suite.NoError(err, types.LogMessages.HandleMessageFailed)

			job, err = suite.db.GetJobById(expectedContext, job.ID, false)
			suite.NoError(err, "Failed to get job by id")
			suite.Equal(tt.jobStatus, *job.Info.JobStatusName)

			suite.mb.AssertExpectations(suite.T())
			suite.s.AssertExpectations(suite.T())
		})
	}
}

func (suite *DomainUpdateTestSuite) TestDomainUpdateHandlerWithNameserversAndContact() {
	domainName := fmt.Sprintf("%v.sexy", uuid.NewString())

	domain, err := insertTestDomainForUpdate(suite.db, domainName)
	suite.NoError(err, "Failed to insert test domain")

	domainInfoRequest := ryinterface.DomainInfoRequest{
		Name: domainName,
	}

	expectedContext := context.Background()

	tests := []struct {
		name      string
		nsAdd     []string
		nsRem     []string
		mockFunc  func(suite *DomainUpdateTestSuite, jobId string)
		jobStatus string
	}{
		{
			name:  "Test with nameservers add/rem and contact #1",
			nsAdd: []string{"ns1.test.com", "ns2.test.com"},
			nsRem: []string{"ns3.test.com", "ns4.test.com"},
			mockFunc: func(suite *DomainUpdateTestSuite, jobId string) {
				expectedHeaders := map[string]any{
					"reply_to":       "WorkerJobDomainProvisionUpdate",
					"correlation_id": jobId,
				}

				domainInfoResponse := &ryinterface.DomainInfoResponse{
					Name:        domainName,
					Contacts:    []*common.DomainContact{},
					Nameservers: []string{"ns1.test.com", "ns3.test.com"},
				}

				domainUpdateRequest := &ryinterface.DomainUpdateRequest{
					Name: domainName,
					Add: &ryinterface.DomainAddRemBlock{
						Contacts: []*common.DomainContact{
							{
								Type: common.DomainContact_ADMIN,
								Id:   "admin-handle-to-add",
							},
						},
						Nameservers: []string{"ns2.test.com"},
					},
					Rem: &ryinterface.DomainAddRemBlock{
						Contacts: []*common.DomainContact{
							{
								Type: common.DomainContact_ADMIN,
								Id:   "admin-handle-to-rem",
							},
						},
						Nameservers: []string{"ns3.test.com"},
					},
				}

				suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), types.GetQueryQueue(accreditationName), &domainInfoRequest, mock.Anything).Return(
					messagebus.RpcResponse{
						Server:  suite.s,
						Message: domainInfoResponse,
						Err:     nil,
					},
					nil,
				)

				suite.mb.On("Send", expectedContext, types.GetTransformQueue(accreditationName), domainUpdateRequest, expectedHeaders).Return(nil)
				suite.s.On("MessageBus").Return(suite.mb)
				suite.s.On("Headers").Return(expectedHeaders)
				suite.s.On("Context").Return(expectedContext)
			},
			jobStatus: "processing",
		},
	}

	for _, tt := range tests {
		suite.Run(tt.name, func() {
			suite.SetupTest()

			service := NewWorkerService(suite.mb, suite.db, suite.tracer)

			nsAdd := make([]*types.Nameserver, len(tt.nsAdd))
			for i, ns := range tt.nsAdd {
				nsAdd[i] = &types.Nameserver{Name: ns}
			}

			nsRem := make([]*types.Nameserver, len(tt.nsRem))
			for i, ns := range tt.nsRem {
				nsRem[i] = &types.Nameserver{Name: ns}
			}

			job, _, err := insertDomainUpdateTestJobWithNameservers(suite.db, domain, nsAdd, nsRem, true)
			suite.NoError(err, "Failed to insert test job")

			msg := &jobmessage.Notification{
				JobId:          job.ID,
				Type:           "domain_update",
				Status:         "status",
				ReferenceId:    "0268f162-5d83-44d2-894a-ab7578c498fb",
				ReferenceTable: "1234",
			}

			tt.mockFunc(suite, job.ID)

			handler := service.DomainUpdateHandler
			err = handler(suite.s, msg)
			suite.NoError(err, types.LogMessages.HandleMessageFailed)

			job, err = suite.db.GetJobById(expectedContext, job.ID, false)
			suite.NoError(err, "Failed to get job by id")
			suite.Equal(tt.jobStatus, *job.Info.JobStatusName)

			suite.mb.AssertExpectations(suite.T())
			suite.s.AssertExpectations(suite.T())
		})
	}
}

func (suite *DomainUpdateTestSuite) TestUnMarshallSecDns() {
	j := `{"pw": null, "name": "tdp-test-1-1725547074.help", "locks": null, "secdns": {"add": {"ds_data": [{"digest": "new-digest", "key_tag": 1, "key_data": {"flags": 0, "protocol": 3, "algorithm": 3, "public_key": "new-pub-key"}, "algorithm": 3, "digest_type": 1}], "key_data": null}, "rem": {"ds_data": [{"digest": "test-digest", "key_tag": 1, "key_data": null, "algorithm": 3, "digest_type": 1}], "key_data": null}, "max_sig_life": null}, "contacts": null, "metadata": {"order_id": "d0453cb4-8d9d-46b5-859d-9222a001a67f"}, "nameservers": null, "accreditation": {"is_proxy": false, "tenant_id": "26ac88c7-b774-4f56-938b-9f7378cb3eca", "provider_id": "2fa525e6-3dc1-4ff2-9630-0a8f368ea63a", "tenant_name": "opensrs", "provider_name": "trs", "accreditation_id": "34bb3610-0aa1-4620-8c50-544dcc3eb244", "accreditation_name": "opensrs-uniregistry", "provider_instance_id": "26da25a2-9bfa-4990-9e41-5286e78bba04", "provider_instance_name": "trs-uniregistry"}, "order_metadata": {"order_id": "d0453cb4-8d9d-46b5-859d-9222a001a67f"}, "accreditation_tld": {"tld_id": "0ceeafe9-beea-4999-bd80-14ef65fa58f7", "is_proxy": false, "tld_name": "help", "tenant_id": "26ac88c7-b774-4f56-938b-9f7378cb3eca", "is_default": true, "provider_id": "2fa525e6-3dc1-4ff2-9630-0a8f368ea63a", "registry_id": "ea120ca2-1beb-4daf-90d4-0a6d27e141b0", "tenant_name": "opensrs", "provider_name": "trs", "registry_name": "unr-registry", "accreditation_id": "34bb3610-0aa1-4620-8c50-544dcc3eb244", "accreditation_name": "opensrs-uniregistry", "accreditation_tld_id": "861b7b18-9194-444a-90eb-930246a85d3e", "provider_instance_id": "26da25a2-9bfa-4990-9e41-5286e78bba04", "provider_instance_name": "trs-uniregistry"}, "tenant_customer_id": "d50ff47e-2a80-4528-b455-6dc5d200ecbe", "provision_domain_update_id": "16aaaaac-150d-4186-98da-03b21bb9a29f", "is_add_update_lock_with_domain_content_supported": true, "is_rem_update_lock_with_domain_content_supported": false}`

	data := new(types.DomainUpdateData)

	err := json.Unmarshal([]byte(j), data)
	suite.NoError(err, "Failed to unmarshal json")

	suite.Empty(data.SecDNSData.AddData.KeyData, "KeyData should be empty")
	suite.Empty(data.SecDNSData.RemData.KeyData, "KeyData should be empty")
	suite.Equal(1, len(*data.SecDNSData.AddData.DSData), "DSData should have 1 element")
	suite.Equal(1, len(*data.SecDNSData.RemData.DSData), "DSData should have 1 element")
}

func (suite *DomainUpdateTestSuite) TestDomainProvisionHandlerWithSecDNS() {
	domainName := fmt.Sprintf("%v.sexy", uuid.NewString())

	domain, err := insertTestDomainForUpdate(suite.db, domainName)
	suite.NoError(err, "Failed to insert test domain")

	job, data, err := insertDomainUpdateTestJob(suite.db, domain, false, false, true, nil)
	suite.NoError(err, "Failed to insert test job")

	msg := &jobmessage.Notification{
		JobId:          job.ID,
		Type:           "provision_domain_update",
		Status:         "status",
		ReferenceId:    "0268f162-5d83-44d2-894a-ab7578c498fb",
		ReferenceTable: "1234",
	}

	expectedContext := context.Background()
	expectedDestination := types.GetTransformQueue(accreditationName)

	msl := uint32(5)
	expectedsecdnsExtension, _ := anypb.New(&extension.SecdnsUpdateRequest{
		Rem: &extension.SecdnsUpdateRequest_Rem{
			Data: &extension.SecdnsUpdateRequest_Rem_DsSet{
				DsSet: &extension.DsDataSet{
					DsData: []*extension.DsData{
						{
							KeyTag:     1,
							Alg:        3,
							DigestType: 1,
							Digest:     "old-digest",
						},
					},
				},
			},
		},
		Add: &extension.SecdnsUpdateRequest_Add{
			Data: &extension.SecdnsUpdateRequest_Add_DsSet{
				DsSet: &extension.DsDataSet{
					DsData: []*extension.DsData{
						{
							KeyTag:     1,
							Alg:        3,
							DigestType: 1,
							Digest:     "new-digest",
						},
					},
				},
			},
		},
		Chg: &extension.SecdnsUpdateRequest_Chg{
			MaxSigLife: &msl,
		},
	})

	expectedMsg := ryinterface.DomainUpdateRequest{
		Name:       data.Name,
		Extensions: map[string]*anypb.Any{"secdns": expectedsecdnsExtension},
	}

	expectedHeaders := map[string]any{
		"reply_to":       "WorkerJobDomainProvisionUpdate",
		"correlation_id": job.ID,
	}

	service := NewWorkerService(suite.mb, suite.db, suite.tracer)

	suite.mb.On("Send", expectedContext, expectedDestination, &expectedMsg, expectedHeaders).Return(nil)
	suite.s.On("MessageBus").Return(suite.mb)
	suite.s.On("Headers").Return(expectedHeaders)
	suite.s.On("Context").Return(expectedContext)

	handler := service.DomainUpdateHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}

func (suite *DomainUpdateTestSuite) TestDomainProvisionHandlerWithLocks() {
	domainName := fmt.Sprintf("%v.sexy", uuid.NewString())

	domain, err := insertTestDomainForUpdate(suite.db, domainName)
	suite.NoError(err, "Failed to insert test domain")

	domainInfoRequest := ryinterface.DomainInfoRequest{
		Name: domainName,
	}

	expectedContext := context.Background()

	tests := []struct {
		name                string
		domainInfoStatuses  []string
		dbLocks             map[string]bool
		domainUpdateRequest *ryinterface.DomainUpdateRequest
		jobStatus           string
	}{
		{
			name:               "Test lock already set (should not add again)",
			domainInfoStatuses: []string{"clientUpdateProhibited"},
			dbLocks: map[string]bool{
				"update": true,
			},
			domainUpdateRequest: &ryinterface.DomainUpdateRequest{
				Name: domainName,
			},
			jobStatus: "completed",
		},
		{
			name:               "Test lock not set (should add)",
			domainInfoStatuses: []string{},
			dbLocks: map[string]bool{
				"update": true,
			},
			domainUpdateRequest: &ryinterface.DomainUpdateRequest{
				Name: domainName,
				Add: &ryinterface.DomainAddRemBlock{
					Status: []string{"clientUpdateProhibited"},
				},
			},
			jobStatus: "processing",
		},
		{
			name:               "Test lock set in domain info but not in db (should remove)",
			domainInfoStatuses: []string{"clientUpdateProhibited"},
			dbLocks: map[string]bool{
				"update": false,
			},
			domainUpdateRequest: &ryinterface.DomainUpdateRequest{
				Name: domainName,
				Rem: &ryinterface.DomainAddRemBlock{
					Status: []string{"clientUpdateProhibited"},
				},
			},
			jobStatus: "processing",
		},
		{
			name:               "Test lock not set anywhere (no-op)",
			domainInfoStatuses: []string{},
			dbLocks: map[string]bool{
				"update": false,
			},
			domainUpdateRequest: &ryinterface.DomainUpdateRequest{
				Name: domainName,
			},
			jobStatus: "completed",
		},
		{
			name:               "Test multiple locks mixed add/remove/no-op",
			domainInfoStatuses: []string{"clientUpdateProhibited", "clientDeleteProhibited"},
			dbLocks: map[string]bool{
				"update":   false, // should remove
				"delete":   true,  // should not add (already present)
				"transfer": true,  // should add (not present)
				"renew":    false, // should not add (not present)
			},
			domainUpdateRequest: &ryinterface.DomainUpdateRequest{
				Name: domainName,
				Add: &ryinterface.DomainAddRemBlock{
					Status: []string{"clientTransferProhibited"},
				},
				Rem: &ryinterface.DomainAddRemBlock{
					Status: []string{"clientUpdateProhibited"},
				},
			},
			jobStatus: "processing",
		},
	}

	for _, tc := range tests {
		suite.Run(tc.name, func() {
			suite.SetupTest()

			service := NewWorkerService(suite.mb, suite.db, suite.tracer)

			job, _, err := insertDomainUpdateTestJob(suite.db, domain, false, false, false, tc.dbLocks)
			suite.NoError(err, "Failed to insert test job")

			expectedHeaders := map[string]any{
				"reply_to":       "WorkerJobDomainProvisionUpdate",
				"correlation_id": job.ID,
			}

			msg := &jobmessage.Notification{
				JobId:          job.ID,
				Type:           "domain_update",
				Status:         "status",
				ReferenceId:    "0268f162-5d83-44d2-894a-ab7578c498fb",
				ReferenceTable: "1234",
			}

			domainInfoResponse := &ryinterface.DomainInfoResponse{
				Name:     domainName,
				Statuses: tc.domainInfoStatuses,
			}

			suite.mb.On("Call", mock.AnythingOfType("*context.timerCtx"), types.GetQueryQueue(accreditationName), &domainInfoRequest, mock.Anything).Return(
				messagebus.RpcResponse{
					Server:  suite.s,
					Message: domainInfoResponse,
					Err:     nil,
				},
				nil,
			)

			if tc.jobStatus != "completed" {
				suite.mb.On("Send", expectedContext, types.GetTransformQueue(accreditationName), tc.domainUpdateRequest, expectedHeaders).Return(nil)
				suite.s.On("MessageBus").Return(suite.mb)
			}
			suite.s.On("Headers").Return(expectedHeaders)
			suite.s.On("Context").Return(expectedContext)

			handler := service.DomainUpdateHandler
			err = handler(suite.s, msg)
			suite.NoError(err, types.LogMessages.HandleMessageFailed)

			job, err = suite.db.GetJobById(suite.s.Context(), job.ID, false)
			suite.NoError(err, "Failed to get job by id")
			suite.Equal(tc.jobStatus, *job.Info.JobStatusName)

			suite.mb.AssertExpectations(suite.T())
			suite.s.AssertExpectations(suite.T())
		})
	}
}
