package handlers

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/anypb"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	commonmessages "github.com/tucowsinc/tdp-messages-go/message/common"
	jobmessage "github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension"
	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/tracing"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
	"google.golang.org/protobuf/types/known/timestamppb"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

const (
	accreditationName = "test-accreditation"
)

func TestDomainProvisionTestSuite(t *testing.T) {
	suite.Run(t, new(DomainProvisionTestSuite))
}

type DomainProvisionTestSuite struct {
	suite.Suite
	db     database.Database
	mb     *mocks.MockMessageBus
	s      *mocks.MockMessageBusServer
	tracer *oteltrace.Tracer
}

func (suite *DomainProvisionTestSuite) SetupSuite() {
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

func (suite *DomainProvisionTestSuite) SetupTest() {
	suite.mb = &mocks.MockMessageBus{}
	suite.s = &mocks.MockMessageBusServer{}
}

func insertDomainProvisionTestJob(db database.Database, withPrice bool, withSecDNS bool, withClaims bool, withIdn bool) (job *model.Job, data *types.DomainData, err error) {
	tx := db.GetDB()

	var accreditationTldID string
	sql := `SELECT accreditation_tld_id FROM v_accreditation_tld WHERE tld_name = ? AND tenant_name = 'opensrs'`
	err = tx.Raw(sql, "sexy").Scan(&accreditationTldID).Error
	if err != nil {
		return
	}

	data = &types.DomainData{
		Name: "test_domain_name",
		Contacts: []types.DomainContact{
			{
				Type:   "admin",
				Handle: "test_handle",
			},
		},
		Pw: "test_pw",
		Nameservers: []types.Nameserver{
			{Name: "test_server", IpAddresses: []string{"test_address"}},
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
		AccreditationTld: types.AccreditationTld{
			AccreditationTldId: accreditationTldID,
		},
		TenantCustomerId:   "",
		RegistrationPeriod: 10,
		ProviderContactId:  "",
	}

	if withPrice {
		data.Price = &types.OrderPrice{Amount: 1045, Currency: "USD", Fraction: 100}
	}

	if withClaims {
		claimsType := "APPLICATION"
		data.LaunchData = &types.DomainLaunchData{
			Claims: &types.DomainClaimsData{
				Type:  &claimsType,
				Phase: "CLAIMS",
				Notice: []types.ClaimsNotice{
					{
						NoticeId:     "test-notice-id",
						ValidatorId:  nil,
						NotAfter:     time.Time{},
						AcceptedDate: time.Time{},
					},
				},
			},
		}
	}

	if withSecDNS {
		max_sig_life := 5
		data.SecDNS = &types.SecDNSData{
			MaxSigLife: &max_sig_life,
			DsData: &[]types.DSData{
				{
					KeyTag:     1,
					Algorithm:  3,
					DigestType: 1,
					Digest:     "test-digest",
				},
			},
		}
	}

	if withIdn {
		data.IdnData = &types.IdnData{
			IdnUname: "test-idn-uname",
			IdnLang:  "test-idn-lang",
		}
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
	sql = `SELECT job_submit(?, ?, ?, ?)`
	err = tx.Raw(sql, id, "provision_domain_create", "0268f162-5d83-44d2-894a-ab7578c498fb", serializedData).Scan(&jobId).Error
	if err != nil {
		return
	}

	job, err = db.GetJobById(context.Background(), jobId, false)

	return
}

func (suite *DomainProvisionTestSuite) TestDomainProvisionHandler() {
	job, data, err := insertDomainProvisionTestJob(suite.db, false, false, false, false)
	suite.NoError(err, "Failed to insert test job")

	msg := &jobmessage.Notification{
		JobId:          job.ID,
		Type:           "domain_provision",
		Status:         "status",
		ReferenceId:    "0268f162-5d83-44d2-894a-ab7578c498fb",
		ReferenceTable: "1234",
	}

	expectedContext := context.Background()
	expectedDestination := types.GetTransformQueue(accreditationName)

	var expectedContacts []*commonmessages.DomainContact
	periodUnit := commonmessages.PeriodUnit_YEAR
	expectedContacts = append(expectedContacts, &commonmessages.DomainContact{
		Type: commonmessages.DomainContact_ADMIN,
		Id:   "test_handle",
	})
	expectedMsg := ryinterface.DomainCreateRequest{
		Name:        data.Name,
		Period:      data.RegistrationPeriod,
		PeriodUnit:  &periodUnit,
		Contacts:    expectedContacts,
		Pw:          data.Pw,
		Nameservers: []string{"test_server"},
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

	handler := service.DomainProvisionHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}

func (suite *DomainProvisionTestSuite) TestDomainProvisionHandlerWithPrice() {
	job, data, err := insertDomainProvisionTestJob(suite.db, true, false, false, false)
	suite.NoError(err, "Failed to insert test job")

	msg := &jobmessage.Notification{
		JobId:          job.ID,
		Type:           "domain_provision",
		Status:         "status",
		ReferenceId:    "0268f162-5d83-44d2-894a-ab7578c498fb",
		ReferenceTable: "1234",
	}

	expectedContext := context.Background()
	expectedDestination := types.GetTransformQueue(accreditationName)

	var expectedContacts []*commonmessages.DomainContact
	periodUnit := commonmessages.PeriodUnit_YEAR
	expectedContacts = append(expectedContacts, &commonmessages.DomainContact{
		Type: commonmessages.DomainContact_ADMIN,
		Id:   "test_handle",
	})

	expectedExtension, _ := anypb.New(&extension.FeeTransformRequest{Fee: []*extension.FeeFee{{Price: &commonmessages.Money{CurrencyCode: "USD", Units: 10, Nanos: 450000000}}}})
	expectedMsg := ryinterface.DomainCreateRequest{
		Name:        data.Name,
		Period:      data.RegistrationPeriod,
		PeriodUnit:  &periodUnit,
		Contacts:    expectedContacts,
		Pw:          data.Pw,
		Nameservers: []string{"test_server"},
		Extensions:  map[string]*anypb.Any{"fee": expectedExtension},
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

	handler := service.DomainProvisionHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}

func (suite *DomainProvisionTestSuite) TestUnmarshallJobDataWithPrice() {
	j := `{"pw": "9(;!B<d\\obYTGqm", "name": "tdp-test-1-1725478976.help", "price": {"amount": 1045, "currency": "USD", "fraction": 100}, "contacts": [{"type": "billing", "handle": null}, {"type": "tech", "handle": null}, {"type": "admin", "handle": null}, {"type": "registrant", "handle": null}], "metadata": {"order_id": "a683cab1-fd62-4752-893b-381dd778b571"}, "nameservers": null, "accreditation": {"is_proxy": false, "tenant_id": "26ac88c7-b774-4f56-938b-9f7378cb3eca", "provider_id": "2cdc06fa-ed02-4584-a629-b3649fa12305", "tenant_name": "opensrs", "provider_name": "trs", "accreditation_id": "95f2baed-5b5f-4756-a5b4-b6c5bad764f2", "accreditation_name": "opensrs-uniregistry", "provider_instance_id": "9fbb569a-7f5c-4ace-862c-943e9c57f04f", "provider_instance_name": "trs-uniregistry"}, "accreditation_tld": {"tld_id": "e6d3b097-7a19-4da3-99e1-09eead9cd703", "is_proxy": false, "tld_name": "help", "tenant_id": "26ac88c7-b774-4f56-938b-9f7378cb3eca", "is_default": true, "provider_id": "2cdc06fa-ed02-4584-a629-b3649fa12305", "registry_id": "bf84cf8a-a067-4204-a1e5-f99f08fb0e95", "tenant_name": "opensrs", "provider_name": "trs", "registry_name": "unr-registry", "accreditation_id": "95f2baed-5b5f-4756-a5b4-b6c5bad764f2", "accreditation_name": "opensrs-uniregistry", "accreditation_tld_id": "bcfb51e1-fc64-4ee7-a6de-049e06b61f4c", "provider_instance_id": "9fbb569a-7f5c-4ace-862c-943e9c57f04f", "provider_instance_name": "trs-uniregistry"}, "tenant_customer_id": "d50ff47e-2a80-4528-b455-6dc5d200ecbe", "registration_period": 1, "provision_contact_id": "42fc0845-1f09-4833-853b-87d5247493f6"}`
	data := new(types.DomainData)

	err := json.Unmarshal([]byte(j), data)
	suite.NoError(err, "Failed to unmarshal json")

	suite.NotEmpty(data.Price)
	suite.Equal("USD", data.Price.Currency)
	suite.Equal(1045.0, data.Price.Amount)
}

func (suite *DomainProvisionTestSuite) TestDomainProvisionHandlerWithSecDNS() {
	job, data, err := insertDomainProvisionTestJob(suite.db, true, true, false, false)
	suite.NoError(err, "Failed to insert test job")

	msg := &jobmessage.Notification{
		JobId:          job.ID,
		Type:           "domain_provision",
		Status:         "status",
		ReferenceId:    "0268f162-5d83-44d2-894a-ab7578c498fb",
		ReferenceTable: "1234",
	}

	expectedContext := context.Background()
	expectedDestination := types.GetTransformQueue(accreditationName)

	var expectedContacts []*commonmessages.DomainContact
	periodUnit := commonmessages.PeriodUnit_YEAR
	expectedContacts = append(expectedContacts, &commonmessages.DomainContact{
		Type: commonmessages.DomainContact_ADMIN,
		Id:   "test_handle",
	})

	expectedMaxSigLife := uint32(5)
	expectedFeeExtension, _ := anypb.New(&extension.FeeTransformRequest{Fee: []*extension.FeeFee{{Price: &commonmessages.Money{CurrencyCode: "USD", Units: 10, Nanos: 450000000}}}})
	expectedsecdnsExtension, _ := anypb.New(&extension.SecdnsCreateRequest{
		MaxSigLife: &expectedMaxSigLife,
		Data: &extension.SecdnsCreateRequest_DsSet{
			DsSet: &extension.DsDataSet{
				DsData: []*extension.DsData{{Digest: "test-digest", KeyTag: 1, Alg: 3, DigestType: 1}},
			},
		}})
	expectedMsg := ryinterface.DomainCreateRequest{
		Name:        data.Name,
		Period:      data.RegistrationPeriod,
		PeriodUnit:  &periodUnit,
		Contacts:    expectedContacts,
		Pw:          data.Pw,
		Nameservers: []string{"test_server"},
		Extensions:  map[string]*anypb.Any{"fee": expectedFeeExtension, "secdns": expectedsecdnsExtension},
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

	handler := service.DomainProvisionHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}

func (suite *DomainProvisionTestSuite) TestUnmarshallJobDataWithSecDns() {
	j := `{"pw": "9(;!B<d\\obYTGqm", "name": "tdp-test-1-1725478976.help", "secdns": {"ds_data": null, "key_data": [{"flags": 0, "protocol": 3, "algorithm": 3, "public_key": "test-public-key"}], "max_sig_life": null}, "contacts": [{"type": "billing", "handle": null}, {"type": "tech", "handle": null}, {"type": "admin", "handle": null}, {"type": "registrant", "handle": null}], "metadata": {"order_id": "a683cab1-fd62-4752-893b-381dd778b571"}, "nameservers": null, "accreditation": {"is_proxy": false, "tenant_id": "26ac88c7-b774-4f56-938b-9f7378cb3eca", "provider_id": "2cdc06fa-ed02-4584-a629-b3649fa12305", "tenant_name": "opensrs", "provider_name": "trs", "accreditation_id": "95f2baed-5b5f-4756-a5b4-b6c5bad764f2", "accreditation_name": "opensrs-uniregistry", "provider_instance_id": "9fbb569a-7f5c-4ace-862c-943e9c57f04f", "provider_instance_name": "trs-uniregistry"}, "accreditation_tld": {"tld_id": "e6d3b097-7a19-4da3-99e1-09eead9cd703", "is_proxy": false, "tld_name": "help", "tenant_id": "26ac88c7-b774-4f56-938b-9f7378cb3eca", "is_default": true, "provider_id": "2cdc06fa-ed02-4584-a629-b3649fa12305", "registry_id": "bf84cf8a-a067-4204-a1e5-f99f08fb0e95", "tenant_name": "opensrs", "provider_name": "trs", "registry_name": "unr-registry", "accreditation_id": "95f2baed-5b5f-4756-a5b4-b6c5bad764f2", "accreditation_name": "opensrs-uniregistry", "accreditation_tld_id": "bcfb51e1-fc64-4ee7-a6de-049e06b61f4c", "provider_instance_id": "9fbb569a-7f5c-4ace-862c-943e9c57f04f", "provider_instance_name": "trs-uniregistry"}, "tenant_customer_id": "d50ff47e-2a80-4528-b455-6dc5d200ecbe", "registration_period": 1, "provision_contact_id": "42fc0845-1f09-4833-853b-87d5247493f6"}`
	data := new(types.DomainData)

	err := json.Unmarshal([]byte(j), data)
	suite.NoError(err, "Failed to unmarshal json")

	suite.Equal(1, len(*data.SecDNS.KeyData))

	suite.Empty(data.SecDNS.DsData)

	// insert more complicated secdns data and test that it unmarshalls correctly

	j = `{"pw": "U!JX:vbRHbI,]ih<", "name": "tdp-test-1-1725487286.help", "secdns": {"ds_data": [{"digest": "test-digest", "key_tag": 1, "key_data": {"flags": 0, "protocol": 3, "algorithm": 3, "public_key": "test-public-key"}, "algorithm": 3, "digest_type": 1}], "key_data": null, "max_sig_life": 2}, "contacts": [{"type": "billing", "handle": null}, {"type": "tech", "handle": null}, {"type": "admin", "handle": null}, {"type": "registrant", "handle": null}], "metadata": {"order_id": "fbad8c23-51b5-4bb7-b598-31a4514c6252"}, "nameservers": null, "accreditation": {"is_proxy": false, "tenant_id": "26ac88c7-b774-4f56-938b-9f7378cb3eca", "provider_id": "18b2eb33-651f-4065-b0cb-dc19e4140105", "tenant_name": "opensrs", "provider_name": "trs", "accreditation_id": "bcc07eb0-c195-4b19-a6c7-59bd9975a92e", "accreditation_name": "opensrs-uniregistry", "provider_instance_id": "559c0f47-4ae8-43e5-a825-380bf7a08c2e", "provider_instance_name": "trs-uniregistry"}, "accreditation_tld": {"tld_id": "000f5436-cb13-44ab-bae4-84e39e0badf2", "is_proxy": false, "tld_name": "help", "tenant_id": "26ac88c7-b774-4f56-938b-9f7378cb3eca", "is_default": true, "provider_id": "18b2eb33-651f-4065-b0cb-dc19e4140105", "registry_id": "d70407bd-1fe9-4d34-bef4-003ab940c3d5", "tenant_name": "opensrs", "provider_name": "trs", "registry_name": "unr-registry", "accreditation_id": "bcc07eb0-c195-4b19-a6c7-59bd9975a92e", "accreditation_name": "opensrs-uniregistry", "accreditation_tld_id": "987d1732-6a88-4c36-a32d-4922f0b51543", "provider_instance_id": "559c0f47-4ae8-43e5-a825-380bf7a08c2e", "provider_instance_name": "trs-uniregistry"}, "tenant_customer_id": "d50ff47e-2a80-4528-b455-6dc5d200ecbe", "registration_period": 1, "provision_contact_id": "7db0abb8-4e3a-4bf6-8b9b-9149bc71141e"}`

	data = new(types.DomainData)

	err = json.Unmarshal([]byte(j), data)
	suite.NoError(err, "Failed to unmarshal json")

	suite.Equal(1, len(*data.SecDNS.DsData))

	suite.NotEmpty((*data.SecDNS.DsData)[0].KeyData)
	suite.Equal(2, *data.SecDNS.MaxSigLife)
}

func (suite *DomainProvisionTestSuite) TestDomainProvisionHandlerWithClaims() {
	job, data, err := insertDomainProvisionTestJob(suite.db, false, false, true, false)
	suite.NoError(err, "Failed to insert test job")

	msg := &jobmessage.Notification{
		JobId:          job.ID,
		Type:           "domain_provision",
		Status:         "status",
		ReferenceId:    "0268f162-5d83-44d2-894a-ab7578c498fb",
		ReferenceTable: "1234",
	}

	expectedContext := context.Background()
	expectedDestination := types.GetTransformQueue(accreditationName)

	var expectedContacts []*commonmessages.DomainContact
	periodUnit := commonmessages.PeriodUnit_YEAR
	expectedContacts = append(expectedContacts, &commonmessages.DomainContact{
		Type: commonmessages.DomainContact_ADMIN,
		Id:   "test_handle",
	})
	expectedLaunchData, _ := anypb.New(&extension.LaunchCreateRequest{
		CreateType: extension.LaunchCreateType_LCRT_APPLICATION.Enum(),
		Phase:      extension.LaunchPhase_CLAIMS,
		Notice: []*extension.LaunchNotice{
			{
				NoticeId:     "test-notice-id",
				ValidatorId:  nil,
				NotAfter:     timestamppb.New(time.Time{}),
				AcceptedDate: timestamppb.New(time.Time{}),
			},
		},
	})
	expectedMsg := ryinterface.DomainCreateRequest{
		Name:        data.Name,
		Period:      data.RegistrationPeriod,
		PeriodUnit:  &periodUnit,
		Contacts:    expectedContacts,
		Pw:          data.Pw,
		Nameservers: []string{"test_server"},
		Extensions:  map[string]*anypb.Any{"launch": expectedLaunchData},
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

	handler := service.DomainProvisionHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}

func (suite *DomainProvisionTestSuite) TestUnmarshallJobDataWithClaims() {
	j := `{"pw": "9(;!B<d\\obYTGqm", "name": "tdp-test-1-1725478976.help", "launch_data": {"claims": {"type":"APPLICATION","phase":"CLAIMS","notice":[{"noticeId":"test-notice-id","validatorId":"test-validator-id","notAfter":"2024-09-06T14:42:52.681200Z","acceptedDate":"2024-09-06T14:42:52.681201Z"}]}}, "contacts": [{"type": "billing", "handle": null}, {"type": "tech", "handle": null}, {"type": "admin", "handle": null}, {"type": "registrant", "handle": null}], "metadata": {"order_id": "a683cab1-fd62-4752-893b-381dd778b571"}, "nameservers": null, "accreditation": {"is_proxy": false, "tenant_id": "26ac88c7-b774-4f56-938b-9f7378cb3eca", "provider_id": "2cdc06fa-ed02-4584-a629-b3649fa12305", "tenant_name": "opensrs", "provider_name": "trs", "accreditation_id": "95f2baed-5b5f-4756-a5b4-b6c5bad764f2", "accreditation_name": "opensrs-uniregistry", "provider_instance_id": "9fbb569a-7f5c-4ace-862c-943e9c57f04f", "provider_instance_name": "trs-uniregistry"}, "accreditation_tld": {"tld_id": "e6d3b097-7a19-4da3-99e1-09eead9cd703", "is_proxy": false, "tld_name": "help", "tenant_id": "26ac88c7-b774-4f56-938b-9f7378cb3eca", "is_default": true, "provider_id": "2cdc06fa-ed02-4584-a629-b3649fa12305", "registry_id": "bf84cf8a-a067-4204-a1e5-f99f08fb0e95", "tenant_name": "opensrs", "provider_name": "trs", "registry_name": "unr-registry", "accreditation_id": "95f2baed-5b5f-4756-a5b4-b6c5bad764f2", "accreditation_name": "opensrs-uniregistry", "accreditation_tld_id": "bcfb51e1-fc64-4ee7-a6de-049e06b61f4c", "provider_instance_id": "9fbb569a-7f5c-4ace-862c-943e9c57f04f", "provider_instance_name": "trs-uniregistry"}, "tenant_customer_id": "d50ff47e-2a80-4528-b455-6dc5d200ecbe", "registration_period": 1, "provision_contact_id": "42fc0845-1f09-4833-853b-87d5247493f6"}`

	data := new(types.DomainData)

	err := json.Unmarshal([]byte(j), data)
	suite.NoError(err, "Failed to unmarshal json")

	suite.NotEmpty(data.LaunchData)
	suite.Equal(1, len(data.LaunchData.Claims.Notice))
}

func (suite *DomainProvisionTestSuite) TestDomainProvisionHandlerWithIdn() {
	job, data, err := insertDomainProvisionTestJob(suite.db, false, false, false, true)
	suite.NoError(err, "Failed to insert test job")

	msg := &jobmessage.Notification{
		JobId:          job.ID,
		Type:           "domain_provision",
		Status:         "status",
		ReferenceId:    "0268f162-5d83-44d2-894a-ab7578c498fb",
		ReferenceTable: "1234",
	}

	expectedContext := context.Background()
	expectedDestination := types.GetTransformQueue(accreditationName)

	var expectedContacts []*commonmessages.DomainContact
	periodUnit := commonmessages.PeriodUnit_YEAR
	expectedContacts = append(expectedContacts, &commonmessages.DomainContact{
		Type: commonmessages.DomainContact_ADMIN,
		Id:   "test_handle",
	})
	expectedIdnData, _ := anypb.New(&extension.IdnCreateRequest{
		Uname: "test-idn-uname",
		Table: "test-idn-lang",
	})

	expectedMsg := ryinterface.DomainCreateRequest{
		Name:        data.Name,
		Period:      data.RegistrationPeriod,
		PeriodUnit:  &periodUnit,
		Contacts:    expectedContacts,
		Pw:          data.Pw,
		Nameservers: []string{"test_server"},
		Extensions:  map[string]*anypb.Any{"idn": expectedIdnData},
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

	handler := service.DomainProvisionHandler
	err = handler(suite.s, msg)
	suite.NoError(err, types.LogMessages.HandleMessageFailed)

	suite.mb.AssertExpectations(suite.T())
	suite.s.AssertExpectations(suite.T())
}

func (suite *DomainProvisionTestSuite) TestUnmarshallJobDataWithIdn() {
	j := `{"pw": "9(;!B<d\\obYTGqm", "name": "tdp-test-1-1725478976.help", "idn": {"uname": "test-idn-uname", "language": "test-idn-lang"}, "contacts": [{"type": "billing", "handle": null}, {"type": "tech", "handle": null}, {"type": "admin", "handle": null}, {"type": "registrant", "handle": null}], "metadata": {"order_id": "a683cab1-fd62-4752-893b-381dd778b571"}, "nameservers": null, "accreditation": {"is_proxy": false, "tenant_id": "26ac88c7-b774-4f56-938b-9f7378cb3eca", "provider_id": "2cdc06fa-ed02-4584-a629-b3649fa12305", "tenant_name": "opensrs", "provider_name": "trs", "accreditation_id": "95f2baed-5b5f-4756-a5b4-b6c5bad764f2", "accreditation_name": "opensrs-uniregistry", "provider_instance_id": "9fbb569a-7f5c-4ace-862c-943e9c57f04f", "provider_instance_name": "trs-uniregistry"}, "accreditation_tld": {"tld_id": "e6d3b097-7a19-4da3-99e1-09eead9cd703", "is_proxy": false, "tld_name": "help", "tenant_id": "26ac88c7-b774-4f56-938b-9f7378cb3eca", "is_default": true, "provider_id": "2cdc06fa-ed02-4584-a629-b3649fa12305", "registry_id": "bf84cf8a-a067-4204-a1e5-f99f08fb0e95", "tenant_name": "opensrs", "provider_name": "trs", "registry_name": "unr-registry", "accreditation_id": "95f2baed-5b5f-4756-a5b4-b6c5bad764f2", "accreditation_name": "opensrs-uniregistry", "accreditation_tld_id": "bcfb51e1-fc64-4ee7-a6de-049e06b61f4c", "provider_instance_id": "9fbb569a-7f5c-4ace-862c-943e9c57f04f", "provider_instance_name": "trs-uniregistry"}, "tenant_customer_id": "d50ff47e-2a80-4528-b455-6dc5d200ecbe", "registration_period": 1, "provision_contact_id": "42fc0845-1f09-4833-853b-87d5247493f6"}`

	data := new(types.DomainData)

	err := json.Unmarshal([]byte(j), data)
	suite.NoError(err, "Failed to unmarshal json")

	suite.NotEmpty(data.IdnData)
	suite.Equal("test-idn-uname", data.IdnData.IdnUname)
	suite.Equal("test-idn-lang", data.IdnData.IdnLang)
}
