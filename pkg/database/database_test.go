package database

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/encoding/protojson"

	sqlxtypes "github.com/jmoiron/sqlx/types"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

const DateFormat = "2006-01-02 15:04:05"

func TestDatabaseTestSuite(t *testing.T) {
	suite.Run(t, new(DatabaseTestSuite))
}

type DatabaseTestSuite struct {
	suite.Suite
	db  Database
	ctx context.Context
}

func (s *DatabaseTestSuite) SetupSuite() {
	config, err := config.LoadConfiguration("../../.env")
	s.NoErrorf(err, "error reading config from .env: %s", err)

	config.LogLevel = "mute" // suppress log output
	log.Setup(config)

	db, err := New(config.PostgresPoolConfig(), config.GetDBLogLevel())
	s.NoErrorf(err, "error connecting to DB: %s", err)
	s.db = db
	s.ctx = context.Background()
}

func getTestJobData() *types.HostData {
	return &types.HostData{
		HostId:   "",
		HostName: "test_name",
		HostAddrs: []string{
			"192.168.0.1",
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
	}
}

func getTenantCustomerId(db Database) (id string, err error) {
	tx := db.GetDB()
	err = tx.Table("tenant_customer").Select("id").Scan(&id).Error
	return
}

func getAccreditationId(db Database) (id string, err error) {
	tx := db.GetDB()
	err = tx.Table("accreditation").Select("id").Scan(&id).Error
	return
}

func getAccreditationTldId(db Database) (id string, err error) {
	tx := db.GetDB()
	err = tx.Table("accreditation_tld").Select("id").Scan(&id).Error
	return
}

func insertTestProvisionDomain(db Database, name string) (pd *model.ProvisionDomain, err error) {
	tx := db.GetDB()

	accreditationId, err := getAccreditationId(db)
	if err != nil {
		return
	}

	accreditationTldId, err := getAccreditationTldId(db)
	if err != nil {
		return
	}

	tenantCustomerId, err := getTenantCustomerId(db)
	if err != nil {
		return
	}

	pd = &model.ProvisionDomain{
		AccreditationID:    accreditationId,
		AccreditationTldID: accreditationTldId,
		TenantCustomerID:   tenantCustomerId,
		DomainName:         name,
	}

	err = tx.Create(pd).Error

	return
}

func insertTestProvisionContact(db Database) (pc *model.ProvisionContact, err error) {
	tx := db.GetDB()

	accreditationId, err := getAccreditationId(db)
	if err != nil {
		return
	}

	// provision contact must have real contact id
	var contactId string
	sql := `insert into contact (type_id, country) values (tc_id_from_name('contact_type', 'individual'), 'CA') returning id`
	err = tx.Raw(sql).Scan(&contactId).Error
	if err != nil {
		return
	}

	tenantCustomerId, err := getTenantCustomerId(db)
	if err != nil {
		return
	}

	pc = &model.ProvisionContact{
		AccreditationID:  accreditationId,
		TenantCustomerID: tenantCustomerId,
		ContactID:        contactId,
	}

	err = tx.Create(pc).Error

	return
}

func insertTestJob(db Database, data *types.HostData, status string) (jobId string, err error) {
	tx := db.GetDB()

	serializedData, err := json.Marshal(data)
	if err != nil {
		return
	}

	tenantCustomerId, err := getTenantCustomerId(db)
	if err != nil {
		return
	}

	sql := `select job_submit(?, ?, ?, ?)`
	err = tx.Raw(
		sql,
		tenantCustomerId,
		"provision_contact_create",
		"0268f162-5d83-44d2-894a-ab7578c498fb",
		serializedData,
	).Scan(&jobId).Error

	if err != nil {
		return
	}

	if status != "" {
		sql = `update job set status_id=tc_id_from_name('job_status', ?) where id=?`
		err = tx.Exec(sql, status, jobId).Error
		if err != nil {
			return
		}
	}

	return
}

func (s *DatabaseTestSuite) TestWithTransactionCommit() {
	jobData := getTestJobData()
	var jobId string

	s.db.WithTransaction(func(db Database) (err error) {

		jobId, err = insertTestJob(db, jobData, "")
		s.NoError(err, "error inserting test job")

		return
	})

	job, err := s.db.GetJobById(s.ctx, jobId, false)

	s.NoError(err)
	s.Equal(jobId, job.ID)
}

func (s *DatabaseTestSuite) TestWithTransactionRollback() {
	jobData := getTestJobData()
	var jobId string

	s.db.WithTransaction(func(db Database) (err error) {

		jobId, err = insertTestJob(db, jobData, "")
		s.NoError(err, "error inserting test job")

		job, err := db.GetJobById(s.ctx, jobId, false)
		s.NoError(err, "error getting job by id")
		s.Equal(jobId, job.ID)

		err = errors.New("simulated error to trigger rollback")

		return
	})

	_, err := s.db.GetJobById(s.ctx, jobId, false)
	s.ErrorIs(err, ErrNotFound)
}

func (s *DatabaseTestSuite) TestGetJobById() {
	jobData := getTestJobData()

	testCases := []struct {
		status         string
		resultedStatus string
	}{
		{"", "submitted"},
		{"submitted", "submitted"},
		{"processing", "processing"},
	}

	for _, tc := range testCases {
		jobId, err := insertTestJob(s.db, jobData, tc.status)
		s.NoError(err, "error inserting test job")

		job, err := s.db.GetJobById(s.ctx, jobId, false)
		s.NoError(err, "error getting job by id")

		s.Equal(jobId, job.ID)
		s.Equal(tc.resultedStatus, *job.Info.JobStatusName)

		data := new(types.HostData)

		err = json.Unmarshal(job.Info.Data, data)
		s.NoError(err, "error parsing job data")

		s.Equal(data, jobData, "job data does not match")
	}
}

func (s *DatabaseTestSuite) TestGetJobByIdNoRecord() {
	jobId := uuid.New().String()

	_, err := s.db.GetJobById(s.ctx, jobId, false)
	s.ErrorIs(err, ErrNotFound)
}

func (s *DatabaseTestSuite) TestSetJobStatus() {
	jobData := getTestJobData()

	// create test job in DB
	jobId, err := insertTestJob(s.db, jobData, "")
	s.NoError(err, "error inserting test job")

	// fetch the job
	job, err := s.db.GetJobById(s.ctx, jobId, true)
	s.NoError(err, "error getting job by id")
	s.Equal(job.StatusID, s.db.GetJobStatusId("submitted"))

	// update status
	err = s.db.SetJobStatus(s.ctx, job, "processing", nil)
	s.NoError(err, "error setting job status")
	s.Equal(job.StatusID, s.db.GetJobStatusId("processing"))

	s.Equal(*job.Info.JobStatusName, "processing")

	// fetch again for checking
	updatedJob, err := s.db.GetJobById(s.ctx, jobId, true)
	s.NoError(err, "error getting job by id")
	s.Equal(updatedJob.StatusID, s.db.GetJobStatusId("processing"))
}

func (s *DatabaseTestSuite) TestSetJobStatusWithResultData() {
	jobData := getTestJobData()
	jobResultData := types.JobResultData{
		Message: &ryinterface.ContactInfoRequest{
			Id: "dummy-id",
			Pw: "dummy-pw",
		}}

	// create test job in DB
	jobId, err := insertTestJob(s.db, jobData, "")
	s.NoError(err, "error inserting test job")

	// fetch the job
	job, err := s.db.GetJobById(s.ctx, jobId, true)
	s.NoError(err, "error getting job by id")
	s.Equal(job.StatusID, s.db.GetJobStatusId("submitted"))

	// initial result data is empty
	s.Equal(job.ResultData, sqlxtypes.JSONText(nil))

	// update status
	err = s.db.SetJobStatus(s.ctx, job, "", &jobResultData)
	s.NoError(err, "error setting job status")

	// status should still be same
	s.Equal(job.StatusID, s.db.GetJobStatusId("submitted"))

	// fetch again for checking
	updatedJob, err := s.db.GetJobById(s.ctx, jobId, true)
	s.NoError(err, "error getting job by id")

	// status should still be same
	s.Equal(updatedJob.StatusID, s.db.GetJobStatusId("submitted"))

	// check if result data message was set
	message := new(ryinterface.ContactInfoRequest)
	err = protojson.Unmarshal(updatedJob.Info.ResultData, message)
	s.NoError(err, "error parsing result data")

	s.Equal(message, jobResultData.Message)

}

func (s *DatabaseTestSuite) TestSetJobStatusInvalidStatus() {
	jobData := getTestJobData()
	testStatus := "not-existing-status"

	// create test job in DB
	jobId, err := insertTestJob(s.db, jobData, "")
	s.NoError(err, "error inserting test job")

	// fetch the job
	job, err := s.db.GetJobById(s.ctx, jobId, true)
	s.NoError(err, "error getting job by id")
	s.Equal(job.StatusID, s.db.GetJobStatusId("submitted"))

	// update status
	err = s.db.SetJobStatus(s.ctx, job, testStatus, nil)
	s.Error(err, "error setting job status: %v", err)

	// check status did nto change
	s.Error(err, fmt.Errorf("invalid status %q", testStatus))

}

func (s *DatabaseTestSuite) TestSetProvisionContactHandle() {
	testHandle := "qwertyuiop"

	provisionContact, err := insertTestProvisionContact(s.db)
	s.NoError(err, "error inserting test provision contact record")

	s.Nil(provisionContact.Handle, "initial value of handle must be nil")

	err = s.db.SetProvisionContactHandle(s.ctx, provisionContact.ID, testHandle)
	s.NoError(err, "error setting contact handle")

	// fetch for checking
	var updatedProvisionContact model.ProvisionContact

	tx := s.db.GetDB()
	err = tx.First(&updatedProvisionContact, "id = ?", provisionContact.ID).Error
	s.NoError(err, "error fetching provision contact from DB")

	s.Equal(testHandle, *updatedProvisionContact.Handle)
}

func (s *DatabaseTestSuite) TestSetProvisionDomainCreatedDateExpiryDate() {
	testDomainName := fmt.Sprintf("%v.com", uuid.New().String())

	testRyCreatedDate, err := time.Parse(DateFormat, "2023-06-29 14:05:05")
	s.NoError(err, "error parsing test ry created date")

	testRyExpiryDate, err := time.Parse(DateFormat, "2025-06-29 14:05:05")
	s.NoError(err, "error parsing test ry expiry date")

	provisionDomain, err := insertTestProvisionDomain(s.db, testDomainName)
	s.NoError(err, "error inserting test provision domain record")

	s.Nil(provisionDomain.RyCreatedDate, "initial value of ry_created_date must be nil")
	s.Nil(provisionDomain.RyExpiryDate, "initial value of ry_expiry_date must be nil")

	provisionDomain.RyCreatedDate = &testRyCreatedDate
	provisionDomain.RyExpiryDate = &testRyExpiryDate

	err = s.db.UpdateProvisionDomain(s.ctx, provisionDomain)
	s.NoError(err, "error setting dates for provision domain record")

	// fetch for checking
	var updatedProvisionDomain model.ProvisionDomain

	tx := s.db.GetDB()
	err = tx.First(&updatedProvisionDomain, "id = ?", provisionDomain.ID).Error
	s.NoError(err, "error fetching provision domain from DB")

	// safe way to compare time objects
	s.WithinDuration(testRyCreatedDate, *updatedProvisionDomain.RyCreatedDate, 0)
	s.WithinDuration(testRyExpiryDate, *updatedProvisionDomain.RyExpiryDate, 0)
}

func (s *DatabaseTestSuite) TestUpdatePDNilDates() {
	testDomainName := fmt.Sprintf("%v.com", uuid.New().String())

	provisionDomain, err := insertTestProvisionDomain(s.db, testDomainName)
	s.NoError(err, "error inserting test provision domain record")

	s.Nil(provisionDomain.RyCreatedDate, "initial value of ry_created_date must be nil")
	s.Nil(provisionDomain.RyExpiryDate, "initial value of ry_expiry_date must be nil")

	err = s.db.UpdateProvisionDomain(s.ctx, provisionDomain)
	s.NoError(err, "error setting dates for provision domain record")

	// fetch for checking
	var updatedProvisionDomain model.ProvisionDomain

	tx := s.db.GetDB()
	err = tx.First(&updatedProvisionDomain, "id = ?", provisionDomain.ID).Error
	s.NoError(err, "error fetching provision domain from DB")

	s.Nil(updatedProvisionDomain.RyExpiryDate, "expiry date should be nil")
	s.Nil(updatedProvisionDomain.RyCreatedDate, "created date should be nil")
}

func (s *DatabaseTestSuite) TestGetProvisionHostingCertificate() {
	// prepare a test record, use data from it to test the two cases
	tx := s.db.GetDB()

	test_domain := fmt.Sprintf("test-%s.link", uuid.New().String())

	var orderId, hostingId, provisionId string

	// create test order
	tx.Raw(`
		INSERT INTO "order"
			(tenant_customer_id, type_id)
			VALUES ((SELECT id FROM tenant_customer LIMIT 1), 
			(SELECT id FROM v_order_type WHERE product_name='hosting' AND name='create'))
			RETURNING id
	`).Scan(&orderId)

	var hostingClientId string

	// create test order_items
	err := tx.Raw(`
		INSERT INTO order_item_create_hosting_client(
            tenant_customer_id,
            email
        ) VALUES(
            (SELECT id FROM tenant_customer LIMIT 1),
            'test@email.com'
        ) RETURNING id 
	`).Scan(&hostingClientId).Error

	if err != nil {
		return
	}

	tx.Raw(`
		INSERT INTO order_item_create_hosting(
        order_id,
        tenant_customer_id,
        client_id,
        domain_name,
        product_id,
        region_id
		) VALUES(
			$1::UUID,
			(SELECT id FROM tenant_customer LIMIT 1),
			$2::UUID,
			$3,
			tc_id_from_name('hosting_product','Wordpress'),
			tc_id_from_name('hosting_region', 'US East (N. Virginia)')
		) RETURNING id
	`, orderId, hostingClientId, test_domain).Scan(&hostingId)

	// create provision_hosting_certificate_create record
	// insert test job, process it
	// check provision record, should be completed

	tx.Raw(`
		INSERT INTO provision_hosting_certificate_create (
				domain_name,
				hosting_id,
				tenant_customer_id,
				order_metadata,
				order_item_plan_ids
			) VALUES (
			 			$1,
						$2,
						(SELECT id FROM tenant_customer LIMIT 1),
						$3,
						ARRAY[$4::UUID]
					) RETURNING id
	`, test_domain, hostingId, "{}", uuid.New()).Scan(&provisionId)

	tests := []struct {
		provivisonRecord *model.ProvisionHostingCertificateCreate
	}{
		{
			provivisonRecord: &model.ProvisionHostingCertificateCreate{
				DomainName: test_domain,
			},
		},
		{
			provivisonRecord: &model.ProvisionHostingCertificateCreate{
				HostingID: hostingId,
			},
		},
	}

	for _, test := range tests {
		res, err := s.db.GetProvisionHostingCertififcate(s.ctx, test.provivisonRecord)

		s.NoError(err, "error fetching provision hosting certificate")

		// check both as when we lookup via domain name it will already be populated and vice versa
		s.Equal(hostingId, res.HostingID)
		s.Equal(test_domain, res.DomainName)

	}
}

func (suite *DatabaseTestSuite) TestUpdateProvisionHostingCreate() {
	tx := suite.db.GetDB()
	var (
		existingID      string
		hostingStatusID = suite.db.GetHostingStatusId("Requested")
	)
	{
		tx.Raw(`
WITH tc_id AS (
    SELECT id FROM tenant_customer LIMIT 1
)
INSERT INTO provision_hosting_create (tenant_customer_id, hosting_id, domain_name, product_id, region_id, client_id)
VALUES ((SELECT id FROM tc_id), gen_random_uuid(), concat(gen_random_uuid()::text,'.help'), (SELECT id FROM hosting_product LIMIT 1), (SELECT id FROM hosting_region LIMIT 1), (SELECT id FROM order_item_create_hosting_client WHERE tenant_customer_id=(SELECT id FROM tc_id) LIMIT 1))
RETURNING id`).Scan(&existingID)
	}

	tests := []struct {
		name string
		upd  *model.ProvisionHostingCreate
		cond interface{}

		expectedError error
		requireRecord func(rec model.ProvisionHostingCreate)
	}{
		{
			name: "update existing record",
			upd:  &model.ProvisionHostingCreate{HostingStatusID: types.ToPointer(hostingStatusID)},
			cond: map[string]interface{}{"id": existingID},

			requireRecord: func(rec model.ProvisionHostingCreate) {
				suite.Require().Equal(hostingStatusID, *rec.HostingStatusID)
			},
		},
		{
			name: "not found",
			upd:  &model.ProvisionHostingCreate{HostingStatusID: types.ToPointer(hostingStatusID)},
			cond: &model.ProvisionHostingCreate{ID: uuid.NewString(), TenantCustomerID: uuid.NewString()},

			expectedError: ErrNotFound,
			requireRecord: func(rec model.ProvisionHostingCreate) {
				suite.Require().Equalf(model.ProvisionHostingCreate{}, rec, "Expected empty record, got: %v", rec)
			},
		},
	}

	for _, tt := range tests {
		tt := tt
		suite.Run(tt.name, func() {
			err := suite.db.UpdateProvisionHostingCreate(context.Background(), tt.upd, tt.cond)
			suite.Require().Equal(tt.expectedError, err, "Expected error: %v, got: %v", tt.expectedError, err)

			rec := model.ProvisionHostingCreate{}
			tx.Model(rec).Where(tt.cond).First(&rec)
			tt.requireRecord(rec)
		})
	}
}
