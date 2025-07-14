package database

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgerrcode"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jackc/pgx/v5/stdlib"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
	"gorm.io/gorm/logger"

	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/enumerator"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

var (
	ErrNotFound          = errors.New("not found")
	ErrInvalidId         = errors.New("invalid id format")
	ErrPollMessageInsert = errors.New("poll message insertion failed")
)

// Database represents the database layer
type Database interface {
	Ping(ctx context.Context) error

	// Transaction
	GetDB() *gorm.DB

	Begin() Database
	Commit() error
	Rollback() error
	WithTransaction(f func(Database) error) (err error)
	Close()

	//General
	GetAccreditationByName(ctx context.Context, name string) (acc *model.Accreditation, err error)
	GetAccreditationById(ctx context.Context, id string) (acc *model.Accreditation, err error)

	// Order Plan
	UpdateOrderItemPlan(ctx context.Context, pd *model.OrderItemPlan) error

	// Job
	GetJobById(ctx context.Context, id string, lock bool) (job *model.Job, err error)
	GetJobByEventId(ctx context.Context, eventId string, lock bool) (job *model.Job, err error)
	SetJobStatus(ctx context.Context, job *model.Job, status string, jrd *types.JobResultData) error
	UpdateJob(ctx context.Context, job *model.Job) error

	// Contact
	SetProvisionContactHandle(ctx context.Context, id string, handle string) error

	// Domain
	GetDomain(ctx context.Context, domain *model.Domain) (result *model.Domain, err error)
	GetVDomain(ctx context.Context, domain *model.VDomain) (result *model.VDomain, err error)
	UpdateDomain(ctx context.Context, domain *model.Domain) (err error)
	DeleteDomainWithReason(ctx context.Context, id string, reason string) (err error)
	SetProvisionDomainStatus(ctx context.Context, id string, status string) (err error)
	GetVProvisionDomain(ctx context.Context, pd *model.VProvisionDomain) (result *model.VProvisionDomain, err error)
	GetProvisionDomain(ctx context.Context, id string) (pd *model.ProvisionDomain, err error)
	GetProvisionDomainRenew(ctx context.Context, id string) (pdr *model.ProvisionDomainRenew, err error)
	GetProvisionDomainRedeem(ctx context.Context, id string) (prd *model.ProvisionDomainRedeem, err error)
	GetProvisionDomainDelete(ctx context.Context, id string) (pdd *model.ProvisionDomainDelete, err error)
	GetProvisionDomainTransferIn(ctx context.Context, id string) (pdti *model.ProvisionDomainTransferIn, err error)
	GetProvisionDomainTransferInRequest(ctx context.Context, pdtr *model.ProvisionDomainTransferInRequest) (*model.ProvisionDomainTransferInRequest, error)
	GetExpiredPendingProvisionDomainTransferInRequests(ctx context.Context, batchSize int) (result []model.ProvisionDomainTransferInRequest, err error)
	UpdateProvisionDomain(ctx context.Context, pd *model.ProvisionDomain) error
	UpdateProvisionDomainUpdate(ctx context.Context, pdu *model.ProvisionDomainUpdate) error
	UpdateProvisionDomainDelete(ctx context.Context, pdd *model.ProvisionDomainDelete) error
	UpdateProvisionDomainRenew(ctx context.Context, pdrn *model.ProvisionDomainRenew) error
	UpdateProvisionDomainRedeem(ctx context.Context, pdrd *model.ProvisionDomainRedeem) error
	UpdateProvisionDomainTransferInRequest(ctx context.Context, pdtr *model.ProvisionDomainTransferInRequest) error
	UpdateProvisionDomainTransferIn(ctx context.Context, pdti *model.ProvisionDomainTransferIn) error
	CreateDomainRgpStatus(ctx context.Context, drs *model.DomainRgpStatus) (err error)
	GetActionableTransferAwayOrders(ctx context.Context, batchSize int) (result []model.VOrderTransferAwayDomain, err error)
	GetDomainAccreditation(ctx context.Context, domainName string) (*model.DomainWithAccreditation, error)
	GetPurgeableDomains(ctx context.Context, batchSize int) (result []model.VDomain, err error)
	CreateDsDataSet(ctx context.Context, dsDataSet []model.TransferInDomainSecdnsDsDatum) error
	CreateKeyDataSet(ctx context.Context, keyDataSet []model.TransferInDomainSecdnsKeyDatum) error

	// Hosting
	UpdateProvisionHostingCreate(ctx context.Context, upd *model.ProvisionHostingCreate, cond interface{}) error
	SetProvisionHostingUpdateDetails(ctx context.Context, id string, status string) (err error)
	SetProvisionHostingDeleteDetails(ctx context.Context, id string, status string, isDeleted bool) (err error)
	GetHosting(ctx context.Context, hosting *model.Hosting) (result *model.Hosting, err error)
	UpdateHosting(ctx context.Context, hosting *model.Hosting) (err error)

	// Certificate
	GetProvisionHostingCertififcate(ctx context.Context, provisionCertificate *model.ProvisionHostingCertificateCreate) (result *model.ProvisionHostingCertificateCreate, err error)
	UpdateProvisionHostingCertificate(ctx context.Context, provisionCertificate *model.ProvisionHostingCertificateCreate) (err error)

	// Enums functions to fetch enum tables values
	GetJobStatusId(name string) string
	GetJobStatusName(id string) string
	GetJobTypeName(id string) string
	GetProvisionStatusId(name string) string
	GetProvisionStatusName(id string) string
	GetDomainContactTypeName(id string) string
	GetDomainContactTypeId(name string) string
	GetPollMessageTypeId(name string) string
	GetPollMessageTypeName(id string) string
	GetPollMessageStatusName(id string) string
	GetPollMessageStatusId(name string) string
	GetRgpStatusId(name string) string
	GetOrderItemPlanStatusId(name string) string
	GetOrderItemPlanStatusName(id string) string
	GetOrderItemPlanValidationStatusId(name string) string
	GetOrderItemPlanValidationStatusName(id string) string
	GetTransferStatusId(name string) string
	GetTransferStatusName(id string) string
	GetOrderTypeId(string, string) string
	GetOrderTypeName(id string) (name string, productName string)
	GetHostingStatusName(string) string
	GetHostingStatusId(string) string

	// Temporary to get TLD settings
	GetTLDSetting(ctx context.Context, accreditationTldID string, key string) (attribute *model.VAttribute, err error)

	// Poll
	CreatePollMessage(ctx context.Context, message *model.PollMessage) (err error)
	UpdatePollMessageStatus(ctx context.Context, messageId string, status string) error

	// Host
	GetHost(ctx context.Context, host *model.Host) (result *model.Host, err error)

	// job_scheduler
	GetStaleJobs(ctx context.Context) ([]model.StaleJob, error)

	// Order
	TransferAwayDomainOrder(ctx context.Context, order *model.Order) (err error)
	OrderNextStatus(ctx context.Context, orderId string, isSuccess bool) (err error)
	GetTransferAwayOrder(ctx context.Context, orderStatus, domainName, tenantID string) (result *model.OrderItemTransferAwayDomain, err error)
	UpdateTransferAwayDomain(ctx context.Context, ota *model.OrderItemTransferAwayDomain) (err error)
	GetOrderItemCreateDomain(ctx context.Context, orderItemId string) (result *model.OrderItemCreateDomain, err error)
	UpdateOrderItemCreateDomain(ctx context.Context, ocd *model.OrderItemCreateDomain) (err error)
	CreateOrder(ctx context.Context, order *model.Order) (err error)
}

// database struct handles the communication with the postgres database
type database struct {
	pool *pgxpool.Pool
	gorm *gorm.DB

	jobStatusEnum                     *enumerator.EnumTable[*model.JobStatus]
	jobTypeEnum                       *enumerator.EnumTable[*model.JobType]
	provisionStatusEnum               *enumerator.EnumTable[*model.ProvisionStatus]
	domainContactTypeEnum             *enumerator.EnumTable[*model.DomainContactType]
	pollMessageTypeEnum               *enumerator.EnumTable[*model.PollMessageType]
	pollMessageStatusEnum             *enumerator.EnumTable[*model.PollMessageStatus]
	rgpStatusEnum                     *enumerator.EnumTable[*model.RgpStatus]
	transferStatusEnum                *enumerator.EnumTable[*model.TransferStatus]
	orderItemPlanStatusEnum           *enumerator.EnumTable[*model.OrderItemPlanStatus]
	orderItemPlanValidationStatusEnum *enumerator.EnumTable[*model.OrderItemPlanValidationStatus]
	orderTypeEnum                     *enumerator.EnumTable[*model.VOrderType]
	hostingStatusEnum                 *enumerator.EnumTable[*model.HostingStatus]
}

// New creates an instance of database and loads enum tables mapping
func New(config *pgxpool.Config, logLevel logger.LogLevel) (db *database, err error) {
	// create pgx pool instance
	pool, err := pgxpool.NewWithConfig(context.Background(), config)
	if err != nil {
		log.Fatal(types.LogMessages.DatabaseConnectionFailed, log.Fields{
			types.LogFieldKeys.Error: err.Error(),
		})
	}

	logger := logger.New(
		log.GetLogger(),
		logger.Config{
			LogLevel:                  logLevel,
			ParameterizedQueries:      true, // do not print query parameters that may include sensitive data like Client email and name, certificate private key
			IgnoreRecordNotFoundError: true, // Ignore ErrRecordNotFound error for logger
		},
	)

	// create gorm instance
	gormDb, err := gorm.Open(
		postgres.New(
			postgres.Config{
				Conn: stdlib.OpenDBFromPool(pool),
			},
		),
		&gorm.Config{
			Logger:         logger,
			TranslateError: true,
		},
	)
	if err != nil {
		return
	}

	jobStatusEnum, err := enumerator.New[*model.JobStatus](gormDb)
	if err != nil {
		err = fmt.Errorf("failed to load JobStatus enumerator: %w", err)
		return
	}

	jobTypeEnum, err := enumerator.New[*model.JobType](gormDb)
	if err != nil {
		err = fmt.Errorf("failed to load JobType enumerator: %w", err)
		return
	}

	provisionStatusEnum, err := enumerator.New[*model.ProvisionStatus](gormDb)
	if err != nil {
		err = fmt.Errorf("failed to load ProvisionStatus type enumerator: %w", err)
		return
	}

	domainContactTypeEnum, err := enumerator.New[*model.DomainContactType](gormDb)
	if err != nil {
		err = fmt.Errorf("failed to load DomainContactType enumerator: %w", err)
		return
	}

	pollMessageTypeEnum, err := enumerator.New[*model.PollMessageType](gormDb)
	if err != nil {
		err = fmt.Errorf("failed to load PollMessagetype enumerator: %w", err)
		return
	}

	pollMessageStatusEnum, err := enumerator.New[*model.PollMessageStatus](gormDb)
	if err != nil {
		err = fmt.Errorf("failed to load PollMessageStatus enumerator: %w", err)
		return
	}

	rgpStatusEnum, err := enumerator.New[*model.RgpStatus](gormDb)
	if err != nil {
		err = fmt.Errorf("failed to load RgpStatus enumerator: %w", err)
		return
	}

	transferStatusEnum, err := enumerator.New[*model.TransferStatus](gormDb)
	if err != nil {
		err = fmt.Errorf("failed to load TransferStatus enumerator: %w", err)
		return
	}

	orderItemPlanStatusEnum, err := enumerator.New[*model.OrderItemPlanStatus](gormDb)
	if err != nil {
		err = fmt.Errorf("failed to load OrderItemPlanStatus enumerator: %w", err)
		return
	}

	orderItemPlanValidationStatusEnum, err := enumerator.New[*model.OrderItemPlanValidationStatus](gormDb)
	if err != nil {
		err = fmt.Errorf("failed to load OrderItemPlanValidationStatus enumerator: %w", err)
		return
	}

	orderTypeEnum, err := enumerator.New[*model.VOrderType](gormDb)
	if err != nil {
		err = fmt.Errorf("failed to load TransferStatus enumerator: %w", err)
		return
	}

	hostingStatusEnum, err := enumerator.New[*model.HostingStatus](gormDb)
	if err != nil {
		err = fmt.Errorf("failed to load hosting status enumerator: %w", err)
		return
	}

	db = &database{
		pool:                              pool,
		gorm:                              gormDb,
		jobStatusEnum:                     &jobStatusEnum,
		jobTypeEnum:                       &jobTypeEnum,
		provisionStatusEnum:               &provisionStatusEnum,
		domainContactTypeEnum:             &domainContactTypeEnum,
		pollMessageTypeEnum:               &pollMessageTypeEnum,
		pollMessageStatusEnum:             &pollMessageStatusEnum,
		rgpStatusEnum:                     &rgpStatusEnum,
		transferStatusEnum:                &transferStatusEnum,
		orderItemPlanStatusEnum:           &orderItemPlanStatusEnum,
		orderItemPlanValidationStatusEnum: &orderItemPlanValidationStatusEnum,
		orderTypeEnum:                     &orderTypeEnum,
		hostingStatusEnum:                 &hostingStatusEnum,
	}

	return
}

// check if the methods expected by the domain.DB are implemented correctly
var _ Database = (*database)(nil)

// Ping checks the connection to the database.
func (db *database) Ping(ctx context.Context) error {
	return db.pool.Ping(ctx)
}

// GetDB returns gorm object or transaction
func (db *database) GetDB() *gorm.DB {
	return db.gorm
}

// Begin returns new instance of database with transaction
func (db *database) Begin() Database {
	return &database{
		gorm:                              db.gorm.Begin(),
		jobStatusEnum:                     db.jobStatusEnum,
		jobTypeEnum:                       db.jobTypeEnum,
		provisionStatusEnum:               db.provisionStatusEnum,
		domainContactTypeEnum:             db.domainContactTypeEnum,
		pollMessageTypeEnum:               db.pollMessageTypeEnum,
		pollMessageStatusEnum:             db.pollMessageStatusEnum,
		rgpStatusEnum:                     db.rgpStatusEnum,
		transferStatusEnum:                db.transferStatusEnum,
		orderItemPlanStatusEnum:           db.orderItemPlanStatusEnum,
		orderItemPlanValidationStatusEnum: db.orderItemPlanValidationStatusEnum,
		orderTypeEnum:                     db.orderTypeEnum,
		hostingStatusEnum:                 db.hostingStatusEnum,
	}
}

// Commit commits all changes made in transaction
func (db *database) Commit() error {
	return db.gorm.Commit().Error
}

// Rollback rollbacks all changes made in transaction
func (db *database) Rollback() error {
	return db.gorm.Rollback().Error
}

// WithTransaction executes function in db transaction, committing on success. Otherwise rolling back.
func (db *database) WithTransaction(f func(Database) error) (err error) {
	log.Debug("Starting transaction")

	tx := db.Begin()

	log.Debug("Transaction started")

	defer func() {
		if err != nil {
			e := tx.Rollback()
			if e != nil {
				log.Error("error rolling back transaction", log.Fields{
					types.LogFieldKeys.Error: e.Error(),
				})
			}

			log.Debug("Transaction rolled back")
			return
		}

		err = tx.Commit()
		if err != nil {
			log.Error("error committing transaction", log.Fields{
				types.LogFieldKeys.Error: err.Error(),
			})
		}

		log.Debug("Transaction committed")
	}()

	return f(tx)
}

func (db *database) Close() {
	db.pool.Close()
}

func (db *database) GetAccreditationByName(ctx context.Context, name string) (acc *model.Accreditation, err error) {
	tx := db.GetDB().WithContext(ctx)

	err = tx.Where("name = ?", name).First(&acc).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			err = ErrNotFound
		}
		return
	}

	return
}

func (db *database) GetAccreditationById(ctx context.Context, id string) (acc *model.Accreditation, err error) {
	tx := db.GetDB().WithContext(ctx)

	err = tx.Where("id = ?", id).First(&acc).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			err = ErrNotFound
		}
		return
	}

	return
}

func (db *database) UpdateOrderItemPlan(ctx context.Context, oip *model.OrderItemPlan) (err error) {
	tx := db.GetDB().WithContext(ctx)

	err = tx.Model(oip).Omit(clause.Associations).Updates(oip).Error
	if errors.Is(err, &pgconn.ConnectError{}) {
		log.Fatal("error updating order item plan %q: %v; exiting...", log.Fields{
			"order_item_plan_id":     oip.ID,
			types.LogFieldKeys.Error: err.Error(),
		})
	}

	return
}

func (db *database) GetJobById(ctx context.Context, id string, lock bool) (job *model.Job, err error) {
	job, err = db.getJobByField(ctx, "id", id, lock)
	if err != nil {
		// This is a temp action to make sure change is backward compatible at all times.
		if errors.Is(err, ErrNotFound) {
			return db.GetJobByEventId(ctx, id, lock)
		}
	}
	return
}

func (db *database) GetJobByEventId(ctx context.Context, eventId string, lock bool) (job *model.Job, err error) {
	return db.getJobByField(ctx, "event_id", eventId, lock)
}

func (db *database) getJobByField(ctx context.Context, name string, value string, lock bool) (job *model.Job, err error) {
	tx := db.GetDB().WithContext(ctx)

	if lock {
		tx = tx.Clauses(clause.Locking{
			Strength: "UPDATE",
			Options:  "NOWAIT",
		})
	}

	filters := map[string]interface{}{name: value}
	job = &model.Job{}

	err = tx.Preload("Info").Limit(1).Find(job, filters).Error
	if errors.Is(err, &pgconn.ConnectError{}) {
		log.Fatal("error getting job, exiting...",
			log.Fields{
				"name":                   name,
				"value":                  value,
				types.LogFieldKeys.Error: err.Error(),
			},
		)
	}

	if job.ID == "" {
		err = ErrNotFound
		return
	}

	return
}

func (db *database) SetJobStatus(ctx context.Context, job *model.Job, status string, jrd *types.JobResultData) (err error) {
	if jrd != nil {
		resultData, err := jrd.MarshalJSON()
		if err != nil {
			log.Error("error converting result data to json", log.Fields{
				types.LogFieldKeys.Error: err.Error(),
			})

			return err
		} else {
			job.ResultData = resultData
		}
	}

	if status != "" {
		statusId := db.GetJobStatusId(status)
		if statusId == "" {
			return fmt.Errorf("invalid status %q", status)
		}

		job.StatusID = statusId

		// update relation as well
		job.Info.JobStatusName = &status
	}

	return db.UpdateJob(ctx, job)
}

func (db *database) UpdateJob(ctx context.Context, job *model.Job) (err error) {
	tx := db.GetDB().WithContext(ctx)

	err = tx.Model(&job).Omit("Info").Updates(job).Error
	if err != nil {
		if errors.Is(err, &pgconn.ConnectError{}) {
			log.Fatal("error updating job, exiting...", log.Fields{
				types.LogFieldKeys.JobID: job.ID,
				types.LogFieldKeys.Error: err.Error(),
			})
		}

		log.Error("error updating job", log.Fields{
			types.LogFieldKeys.JobID: job.ID,
			types.LogFieldKeys.Error: err.Error(),
		})
	}

	return
}

func (db *database) SetProvisionContactHandle(ctx context.Context, id string, handle string) (err error) {
	tx := db.GetDB().WithContext(ctx)

	err = tx.Model(&model.ProvisionContact{}).Where("id = ?", id).Updates(model.ProvisionContact{
		Handle: &handle,
	}).Error

	if errors.Is(err, &pgconn.ConnectError{}) {
		log.Fatal("error updating contact provision, exiting...", log.Fields{
			"id":                     id,
			types.LogFieldKeys.Error: err.Error(),
		})
	}

	return
}

func (db *database) UpdateDomain(ctx context.Context, domain *model.Domain) (err error) {
	tx := db.gorm.WithContext(ctx)

	err = tx.Model(&model.Domain{}).Where("id = ?", domain.ID).Updates(domain).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		err = ErrNotFound
	} else if errors.Is(err, &pgconn.ConnectError{}) {
		log.Fatal("error updating domain, exiting...", log.Fields{
			types.LogFieldKeys.Domain: domain.Name,
			types.LogFieldKeys.Error:  err.Error(),
		})
	}

	return
}

func (db *database) DeleteDomainWithReason(ctx context.Context, id string, reason string) (err error) {
	tx := db.GetDB().WithContext(ctx)

	err = tx.Exec("SELECT delete_domain_with_reason($1, $2)", id, reason).Error
	if errors.Is(err, &pgconn.ConnectError{}) {
		log.Fatal("error deleting domain, exiting...", log.Fields{
			"id":                     id,
			types.LogFieldKeys.Error: err.Error(),
		})
	}

	return
}

func (db *database) UpdateProvisionDomain(ctx context.Context, pd *model.ProvisionDomain) (err error) {
	tx := db.GetDB().WithContext(ctx)

	err = tx.Table("provision_domain").Omit(clause.Associations).Updates(pd).Error
	if errors.Is(err, &pgconn.ConnectError{}) {
		log.Fatal("error updating domain provision, exiting...", log.Fields{
			"id":                     pd.ID,
			types.LogFieldKeys.Error: err.Error(),
		})
	}

	return
}

func (db *database) UpdateProvisionDomainUpdate(ctx context.Context, pdu *model.ProvisionDomainUpdate) (err error) {
	tx := db.GetDB().WithContext(ctx)

	err = tx.Table("provision_domain_update").Omit(clause.Associations).Updates(pdu).Error
	if errors.Is(err, &pgconn.ConnectError{}) {
		log.Fatal("error updating domain update provision, exiting...", log.Fields{
			"id":                     pdu.ID,
			types.LogFieldKeys.Error: err.Error(),
		})
	}

	return
}

func (db *database) UpdateProvisionDomainDelete(ctx context.Context, pdd *model.ProvisionDomainDelete) (err error) {
	tx := db.GetDB().WithContext(ctx)

	err = tx.Table("provision_domain_delete").Omit(clause.Associations).Updates(pdd).Error
	if errors.Is(err, &pgconn.ConnectError{}) {
		log.Fatal("error updating domain delete provision, exiting...", log.Fields{
			"id":                     pdd.ID,
			types.LogFieldKeys.Error: err.Error(),
		})
	}

	return
}

func (db *database) UpdateProvisionDomainRenew(ctx context.Context, pdrn *model.ProvisionDomainRenew) (err error) {
	tx := db.GetDB().WithContext(ctx)

	err = tx.Table("provision_domain_renew").Omit(clause.Associations).Updates(pdrn).Error
	if errors.Is(err, &pgconn.ConnectError{}) {
		log.Fatal("error updating domain renew provision,  exiting...", log.Fields{
			"id":                     pdrn.ID,
			types.LogFieldKeys.Error: err.Error(),
		})
	}

	return
}

func (db *database) UpdateProvisionDomainRedeem(ctx context.Context, pdrd *model.ProvisionDomainRedeem) (err error) {
	tx := db.GetDB().WithContext(ctx)

	err = tx.Table("provision_domain_redeem").Omit(clause.Associations).Updates(pdrd).Error
	if errors.Is(err, &pgconn.ConnectError{}) {
		log.Fatal("error updating domain redeem provision, exiting...", log.Fields{
			"id":                     pdrd.ID,
			types.LogFieldKeys.Error: err.Error(),
		})
	}

	return
}

func (db *database) UpdateProvisionDomainTransferInRequest(ctx context.Context, pdtr *model.ProvisionDomainTransferInRequest) (err error) {
	tx := db.GetDB().WithContext(ctx)

	err = tx.Table("provision_domain_transfer_in_request").Omit(clause.Associations).Updates(pdtr).Error
	if errors.Is(err, &pgconn.ConnectError{}) {
		log.Fatal("error updating domain transfer in request provision, exiting...", log.Fields{
			"provision_id":           pdtr.ID,
			types.LogFieldKeys.Error: err.Error(),
		})
	}

	return
}

func (db *database) UpdateProvisionDomainTransferIn(ctx context.Context, pdti *model.ProvisionDomainTransferIn) (err error) {
	tx := db.GetDB().WithContext(ctx)

	err = tx.Table("provision_domain_transfer_in").Omit(clause.Associations).Updates(pdti).Error
	if errors.Is(err, &pgconn.ConnectError{}) {
		log.Fatal("error updating domain transfer in provision, exiting...", log.Fields{
			"provision_id":           pdti.ID,
			types.LogFieldKeys.Error: err.Error(),
		})
	}

	return
}

// CreateDomainRgpStatus inserts a new rgp status for the domain into the database
func (db *database) CreateDomainRgpStatus(ctx context.Context, drs *model.DomainRgpStatus) (err error) {
	tx := db.GetDB().WithContext(ctx)

	err = tx.Create(&drs).Error
	if err != nil {
		if errors.Is(err, &pgconn.ConnectError{}) {
			log.Fatal("error insert domain rgp status, exiting...", log.Fields{
				types.LogFieldKeys.Error: err.Error(),
			})
		}
		return
	}

	log.Debug("inserted a new rgp status for domain", log.Fields{"status": drs.StatusID, "domain": drs.DomainID})

	return
}

// UpdateProvisionHostingCreate updates provision_hosting_create record based on provided condition
// Returns ErrNotFound if record not found based on provided condition
func (db *database) UpdateProvisionHostingCreate(ctx context.Context, upd *model.ProvisionHostingCreate, cond interface{}) error {
	tx := db.GetDB().WithContext(ctx).Where(cond).Updates(upd)
	if err := tx.Error; err != nil {
		return err
	}
	if tx.RowsAffected == 0 {
		return ErrNotFound
	}
	return nil
}

// SetProvisionHostingUpdateDetails updates the hosting table with response received from the backend
func (db *database) SetProvisionHostingUpdateDetails(ctx context.Context, id string, status string) (err error) {
	tx := db.GetDB().WithContext(ctx)

	provisionHostingUpdate := model.ProvisionHostingUpdate{
		HostingStatusID: types.ToPointer(db.GetHostingStatusId(status)),
	}
	err = tx.Model(&model.ProvisionHostingUpdate{}).Where("id = ?", id).Updates(provisionHostingUpdate).Error
	if errors.Is(err, &pgconn.ConnectError{}) {
		log.Fatal("error updating hosting provision update, exiting...", log.Fields{
			"id":                     id,
			types.LogFieldKeys.Error: err.Error(),
		})
	}
	return
}

// SetProvisionHostingDeleteDetails updates the hosting table with response received from the backend
func (db *database) SetProvisionHostingDeleteDetails(ctx context.Context, id string, status string, isDeleted bool) (err error) {
	tx := db.GetDB().WithContext(ctx)

	provisionHostingDelete := model.ProvisionHostingDelete{
		HostingStatusID: types.ToPointer(db.GetHostingStatusId(status)),
		IsDeleted:       &isDeleted,
	}
	err = tx.Model(&model.ProvisionHostingDelete{}).Where("id = ?", id).Updates(provisionHostingDelete).Error
	if errors.Is(err, &pgconn.ConnectError{}) {
		log.Fatal("error updating hosting provision delete, exiting...", log.Fields{
			"id":                     id,
			types.LogFieldKeys.Error: err.Error(),
		})
	}
	return
}

// GetHosting gets hosting by external order id
func (db *database) GetHosting(ctx context.Context, hosting *model.Hosting) (result *model.Hosting, err error) {
	tx := db.GetDB().WithContext(ctx)

	err = tx.Preload(clause.Associations).Where(&hosting).First(&result).Error
	if err != nil {
		if errors.Is(err, &pgconn.ConnectError{}) {
			log.Fatal("error getting job, exiting...",
				log.Fields{
					"hosting":                hosting,
					types.LogFieldKeys.Error: err.Error(),
				},
			)
		}
		return
	}

	if result.ID == "" {
		err = ErrNotFound
		return
	}

	return
}

// UpdateHosting updates hosting object
func (db *database) UpdateHosting(ctx context.Context, hosting *model.Hosting) (err error) {
	tx := db.GetDB().WithContext(ctx)

	err = tx.Table("ONLY hosting").Omit(clause.Associations).Updates(hosting).Error
	if err != nil && errors.Is(err, &pgconn.ConnectError{}) {
		log.Fatal("error updating hosting, exiting...", log.Fields{
			"hosting":                hosting.ID,
			types.LogFieldKeys.Error: err.Error(),
		})
	}
	return
}

// GetProvisionHostingCertififcate gets the certificate details from the database
func (db *database) GetProvisionHostingCertififcate(ctx context.Context, provisionCertificate *model.ProvisionHostingCertificateCreate) (result *model.ProvisionHostingCertificateCreate, err error) {

	tx := db.GetDB().WithContext(ctx)

	// possibly add check to make sure we have a valid hosting id or domain name

	// find records where hostingid matches and provisioned date is null
	err = tx.Where(&provisionCertificate).
		First(&result).Error

	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			err = ErrNotFound
		}
	}

	return
}

// UpdateProvisionHostingCertificate updates the certificate details in the database
func (db *database) UpdateProvisionHostingCertificate(ctx context.Context, provisionCertificate *model.ProvisionHostingCertificateCreate) (err error) {
	tx := db.GetDB().WithContext(ctx)

	// set status to completed

	err = tx.Table("provision_hosting_certificate_create").Omit(clause.Associations).Updates(provisionCertificate).Error

	if errors.Is(err, &pgconn.ConnectError{}) {
		log.Fatal("error updating hosting certificate provision, exiting...",
			log.Fields{
				"id":                     provisionCertificate.ID,
				types.LogFieldKeys.Error: err.Error(),
			},
		)
	}
	return
}

// GetProvisionDomainRedeem retrieves provision domain redeem from database
func (db *database) GetProvisionDomainRedeem(ctx context.Context, id string) (prd *model.ProvisionDomainRedeem, err error) {
	tx := db.GetDB().WithContext(ctx)

	if err := tx.Where("id = ?", id).Find(&prd).Error; err != nil {
		return nil, err
	}

	return
}

// GetProvisionDomainRenew retrieves provision domain renew from database
func (db *database) GetProvisionDomainRenew(ctx context.Context, id string) (pdr *model.ProvisionDomainRenew, err error) {
	tx := db.GetDB().WithContext(ctx)

	if err := tx.Where("id = ?", id).Find(&pdr).Error; err != nil {
		return nil, err
	}

	return
}

// GetProvisionDomainDelete retrieves provision domain delete from database
func (db *database) GetProvisionDomainDelete(ctx context.Context, id string) (pdd *model.ProvisionDomainDelete, err error) {
	tx := db.GetDB().WithContext(ctx)

	if err := tx.Where("id = ?", id).Find(&pdd).Error; err != nil {
		return nil, err
	}

	return
}

// GetProvisionDomain retrieves provision domain from database
func (db *database) GetProvisionDomain(ctx context.Context, id string) (pd *model.ProvisionDomain, err error) {
	tx := db.GetDB().WithContext(ctx)

	if err := tx.Where("id = ?", id).Find(&pd).Error; err != nil {
		return nil, err
	}

	return
}

// GetVProvisionDomain retrieves provision record looking across all provision domain types
func (db *database) GetVProvisionDomain(ctx context.Context, pd *model.VProvisionDomain) (result *model.VProvisionDomain, err error) {
	tx := db.GetDB().WithContext(ctx)

	err = tx.Where(&pd).First(&result).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			err = ErrNotFound
		}
		return
	}

	return
}

// SetProvisionDomainStatus updates provision domain status
func (db *database) SetProvisionDomainStatus(ctx context.Context, id string, status string) (err error) {
	statusId := db.GetProvisionStatusId(status)
	if statusId == "" {
		return fmt.Errorf("invalid status %q", status)
	}

	tx := db.GetDB().WithContext(ctx)

	err = tx.Model(&model.VProvisionDomain{}).Where("id = ?", id).Update("status_id", statusId).Error
	if err != nil {
		if errors.Is(err, &pgconn.ConnectError{}) {
			log.Fatal("error updating provision domain status, exiting...",
				log.Fields{
					"id":                     id,
					"status":                 status,
					types.LogFieldKeys.Error: err.Error(),
				},
			)
		}

		log.Error("error updating provision domain status",
			log.Fields{
				"id":                     id,
				"status":                 status,
				types.LogFieldKeys.Error: err.Error(),
			},
		)
	}

	return
}

func (db *database) GetTLDSetting(ctx context.Context, accreditationTldID string, key string) (attributes *model.VAttribute, err error) {
	tx := db.GetDB().WithContext(ctx)

	if err := tx.Where("accreditation_tld_id = ? AND key = ?", accreditationTldID, key).Find(&attributes).Error; err != nil {
		return nil, err
	}

	return
}

// GetProvisionDomainTransferIn retrieves provision domain transfer in from database
func (db *database) GetProvisionDomainTransferIn(ctx context.Context, id string) (pdti *model.ProvisionDomainTransferIn, err error) {
	tx := db.GetDB().WithContext(ctx)

	if err := tx.Where("id = ?", id).Find(&pdti).Error; err != nil {
		return nil, err
	}

	return
}

// GetDomain gets the details of an existing domain from the database
func (db *database) GetDomain(ctx context.Context, domain *model.Domain) (result *model.Domain, err error) {
	tx := db.gorm.WithContext(ctx)

	err = tx.Preload(clause.Associations).
		Preload("DomainHosts." + clause.Associations).
		Preload("DomainHosts.Host." + clause.Associations).
		Preload("DomainContacts." + clause.Associations).
		Where(&domain).
		First(&result).Error

	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			err = ErrNotFound
		}
		return
	}

	return
}

// GetVDomain gets the details of an existing domain from the v_domain view
func (db *database) GetVDomain(ctx context.Context, domain *model.VDomain) (result *model.VDomain, err error) {
	tx := db.gorm.WithContext(ctx)

	err = tx.Where(&domain).First(&result).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			err = ErrNotFound
		}
		return
	}

	return
}

// CreatePollMessage inserts the poll message into database
func (db *database) CreatePollMessage(ctx context.Context, message *model.PollMessage) (err error) {
	tx := db.GetDB().WithContext(ctx)

	err = tx.Create(&message).Error
	if errors.Is(err, &pgconn.ConnectError{}) {
		log.Fatal("error insert poll message, exiting...", log.Fields{
			types.LogFieldKeys.Error: err.Error(),
		})
	}

	// Check errors
	var e *pgconn.PgError
	if errors.As(err, &e) {
		switch e.Code {
		case pgerrcode.UniqueViolation:
			log.Warn("poll message already exists")
		default:
			err = ErrPollMessageInsert
		}
		return
	}

	log.Debug("inserted poll message", log.Fields{"message_id": message.ID})

	return
}

func (db *database) UpdatePollMessageStatus(ctx context.Context, messageId string, status string) (err error) {
	tx := db.GetDB().WithContext(ctx)

	// Get statusId
	statusId := db.GetPollMessageStatusId(status)
	if statusId == "" {
		return fmt.Errorf("invalid status %q", status)
	}

	err = tx.Model(&model.PollMessage{}).Where("id = ?", messageId).Update("status_id", statusId).Error
	if err != nil {
		if errors.Is(err, &pgconn.ConnectError{}) {
			log.Fatal("error updating poll message, exiting...", log.Fields{
				"messageId":              messageId,
				types.LogFieldKeys.Error: err.Error(),
			})
		}
		log.Error("error updating poll message", log.Fields{
			"messageId":              messageId,
			types.LogFieldKeys.Error: err.Error(),
		})
	}

	return
}

// GetHost retrieves a host
func (db *database) GetHost(ctx context.Context, host *model.Host) (*model.Host, error) {
	tx := db.gorm.WithContext(ctx)

	if err := tx.Table("host").
		Preload(
			"HostAddrs",
			func(db *gorm.DB) *gorm.DB {
				return db.Table("host_addr")
			},
		).Where(&host).
		First(&host).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	return host, nil
}

func (db *database) GetJobStatusId(name string) string {
	return db.jobStatusEnum.GetByKey(name)
}

func (db *database) GetJobStatusName(id string) string {
	return db.jobStatusEnum.GetByValue(id)
}

func (db *database) GetJobTypeName(id string) string {
	return db.jobTypeEnum.GetByValue(id)
}

func (db *database) GetProvisionStatusId(name string) string {
	return db.provisionStatusEnum.GetByKey(name)
}

func (db *database) GetProvisionStatusName(id string) string {
	return db.provisionStatusEnum.GetByValue(id)
}

// GetDomainContactTypeName gets name by id; where 'name' is key and 'id' is value
func (db *database) GetDomainContactTypeName(id string) string {
	return db.domainContactTypeEnum.GetByValue(id)
}

// GetDomainContactTypeId gets id by name; where 'name' is key and 'id' is value
func (db *database) GetDomainContactTypeId(name string) string {
	return db.domainContactTypeEnum.GetByKey(name)
}

func (db *database) GetPollMessageTypeId(name string) string {
	return db.pollMessageTypeEnum.GetByKey(name)
}

func (db *database) GetPollMessageTypeName(id string) string {
	return db.pollMessageTypeEnum.GetByValue(id)
}

func (db *database) GetPollMessageStatusName(id string) string {
	return db.pollMessageStatusEnum.GetByValue(id)
}

func (db *database) GetPollMessageStatusId(name string) string {
	return db.pollMessageStatusEnum.GetByKey(name)
}

func (db *database) GetRgpStatusId(name string) string {
	return db.rgpStatusEnum.GetByKey(name)
}

func (db *database) GetTransferStatusId(name string) string {
	return db.transferStatusEnum.GetByKey(name)
}

func (db *database) GetTransferStatusName(id string) string {
	return db.transferStatusEnum.GetByValue(id)
}

func (db *database) GetOrderItemPlanStatusId(name string) string {
	return db.orderItemPlanStatusEnum.GetByKey(name)
}

func (db *database) GetOrderItemPlanStatusName(id string) string {
	return db.orderItemPlanStatusEnum.GetByValue(id)
}

func (db *database) GetOrderItemPlanValidationStatusId(name string) string {
	return db.orderItemPlanValidationStatusEnum.GetByKey(name)
}

func (db *database) GetOrderItemPlanValidationStatusName(id string) string {
	return db.orderItemPlanValidationStatusEnum.GetByValue(id)
}

// GetOrderTypeId gets id by name and product name
func (db *database) GetOrderTypeId(name string, productName string) string {
	return db.orderTypeEnum.GetByKey(fmt.Sprintf("%v.%v", name, productName))
}

// GetOrderTypeName gets name and product name by id; where 'name' is key and 'id' is value
func (db *database) GetOrderTypeName(id string) (name string, productName string) {
	n := strings.Split(db.orderTypeEnum.GetByValue(id), ".")
	return n[0], n[1]
}

func (db *database) GetStaleJobs(ctx context.Context) (result []model.StaleJob, err error) {
	tx := db.GetDB().WithContext(ctx)
	err = tx.Raw(`
			  	SELECT
					j.job_id,
					j.job_status_name,
					NOTIFY_EVENT(
						'job_event',
						'job_event_notify',
						JSONB_BUILD_OBJECT(
							'job_id',j.job_id,
							'type',j.job_type_name,
							'status',j.job_status_name,
							'reference_id',j.reference_id,
							'reference_table',j.reference_table,
							'routing_key',j.routing_key,
							'metadata',
							CASE WHEN j.data ? 'metadata' 
							THEN
							(j.data -> 'metadata')
							ELSE
							'{}'::JSONB
							END
						)::TEXT
					)
				FROM v_job j
				WHERE job_id IN (
					SELECT 
						j.id
					FROM job j 
						JOIN job_status js ON js.id=j.status_id
					WHERE js.name = 'submitted' AND j.start_date < NOW()
					FOR UPDATE SKIP LOCKED
				)
			`).Scan(&result).Error

	return
}

func (db *database) GetProvisionDomainTransferInRequest(ctx context.Context, pdtr *model.ProvisionDomainTransferInRequest) (result *model.ProvisionDomainTransferInRequest, err error) {
	tx := db.gorm.WithContext(ctx)

	err = tx.Where(&pdtr).First(&result).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			err = ErrNotFound
		}
		return
	}

	return
}

func (db *database) GetExpiredPendingProvisionDomainTransferInRequests(ctx context.Context, batchSize int) (result []model.ProvisionDomainTransferInRequest, err error) {
	tx := db.GetDB().WithContext(ctx)

	pendingStatusId := db.GetProvisionStatusId(types.ProvisionStatus.PendingAction)
	actionDate := time.Now()
	err = tx.Model(&model.ProvisionDomainTransferInRequest{}).Where("status_id = ?", pendingStatusId).Where("action_date <= ?", actionDate).Scan(&result).Limit(batchSize).Error
	return
}

func (db *database) TransferAwayDomainOrder(ctx context.Context, order *model.Order) (err error) {
	tx := db.gorm.WithContext(ctx)

	err = tx.Create(order).Error

	return
}

func (db *database) UpdateTransferAwayDomain(ctx context.Context, ota *model.OrderItemTransferAwayDomain) (err error) {
	tx := db.gorm.WithContext(ctx)

	err = tx.Table("order_item_transfer_away_domain").Omit(clause.Associations).Updates(ota).Error
	if errors.Is(err, &pgconn.ConnectError{}) {
		log.Fatal("error updating order_item_transfer_away_domain exiting...", log.Fields{
			"messageId":              ota.ID,
			types.LogFieldKeys.Error: err.Error(),
		})
	}

	return
}

func (db *database) OrderNextStatus(ctx context.Context, orderId string, isSuccess bool) (err error) {
	order := new(model.Order)

	err = db.gorm.WithContext(ctx).Model(order).
		Where("id = ?", orderId).
		Clauses(clause.Returning{Columns: []clause.Column{{Name: "status_id"}}}).
		UpdateColumn("status_id", gorm.Expr("order_next_status(?, ?)", orderId, isSuccess)).
		Error

	return
}

func (db *database) GetTransferAwayOrder(ctx context.Context, orderStatus, domainName, tenantID string) (result *model.OrderItemTransferAwayDomain, err error) {
	tx := db.gorm.WithContext(ctx)
	err = tx.Table("order_item_transfer_away_domain AS ota").
		Joins("JOIN \"order\" o ON ota.order_id = o.id").
		Joins("JOIN order_status os ON o.status_id = os.id").
		Joins("JOIN tenant_customer tc ON o.tenant_customer_id = tc.id").
		Where("ota.name = ? AND os.name = ? AND tc.tenant_id = ?", domainName, orderStatus, tenantID).
		Select("ota.*").
		First(&result).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		err = ErrNotFound
	}
	return
}

func (db *database) GetDomainAccreditation(ctx context.Context, domainName string) (*model.DomainWithAccreditation, error) {
	var result model.DomainWithAccreditation
	tx := db.gorm.WithContext(ctx)

	rowsAffected := tx.
		Table("domain AS d").
		Select("d.*, a.*").
		Joins("JOIN accreditation_tld at on at.id = d.accreditation_tld_id ").
		Joins("JOIN accreditation a on a.id = at.accreditation_id").
		Where("d.name = ?", domainName).
		Scan(&result).RowsAffected

	if rowsAffected == 0 && tx.Error == nil {
		return nil, ErrNotFound
	}

	// Check for other errors
	if tx.Error != nil {
		return nil, tx.Error
	}
	return &result, nil
}

func (db *database) GetActionableTransferAwayOrders(ctx context.Context, batchSize int) (result []model.VOrderTransferAwayDomain, err error) {
	tx := db.GetDB().WithContext(ctx)

	// A 2-hour window is given for serverApproved poll messages to be consumed and processed
	// in case the registry submits serverApproved near or on the action_date.
	actionDate := time.Now().Add(-2 * time.Hour)
	err = tx.Model(&model.VOrderTransferAwayDomain{}).
		Where("status_name = ?", types.OrderStatusEnum.Created).
		Where("action_date <= ?", actionDate).
		Scan(&result).Limit(batchSize).Error
	return
}

func (db *database) GetOrderItemCreateDomain(ctx context.Context, orderItemId string) (result *model.OrderItemCreateDomain, err error) {
	if !types.IsValidUUID(orderItemId) {
		err = ErrInvalidId
		return
	}

	tx := db.gorm.WithContext(ctx)
	err = tx.Table("order_item_create_domain AS oicd").
		Where("oicd.id = ?", orderItemId).
		Select("oicd.*").
		First(&result).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		err = ErrNotFound
	}

	return
}

func (db *database) UpdateOrderItemCreateDomain(ctx context.Context, ocd *model.OrderItemCreateDomain) (err error) {
	tx := db.gorm.WithContext(ctx)

	err = tx.Model(ocd).Select("*").Where("id = ?", ocd.ID).Updates(ocd).Error
	if errors.Is(err, &pgconn.ConnectError{}) {
		log.Fatal("error updating order_item_create_domain exiting...", log.Fields{
			"orderItemId":            ocd.ID,
			types.LogFieldKeys.Error: err.Error(),
		})
	}

	return
}

func (db *database) CreateOrder(ctx context.Context, order *model.Order) (err error) {
	tx := db.gorm.WithContext(ctx)

	err = tx.Create(order).Error

	return
}

func (db *database) GetPurgeableDomains(ctx context.Context, batchSize int) (result []model.VDomain, err error) {
	tx := db.GetDB().WithContext(ctx)

	err = tx.Model(&model.VDomain{}).
		Joins("LEFT JOIN domain_rgp_status ON domain_rgp_status.domain_id = v_domain.id").
		Where("v_domain.deleted_date IS NOT NULL").
		Where("v_domain.rgp_epp_status IS NULL OR v_domain.rgp_epp_status != ?", "redemptionPeriod").
		Where("domain_rgp_status.status_id = ?", db.GetRgpStatusId("redemption_grace_period")).
		Where("domain_rgp_status.expiry_date < ?", time.Now()).
		Limit(batchSize).
		Scan(&result).Error

	return
}

// CreateDsDataSet inserts the DsDataSet into the database
func (db *database) CreateDsDataSet(ctx context.Context, dsDataSet []model.TransferInDomainSecdnsDsDatum) error {
	tx := db.GetDB().WithContext(ctx)
	err := tx.Create(dsDataSet).Error
	if err != nil {
		if errors.Is(err, &pgconn.ConnectError{}) {
			log.Fatal("error inserting domain transfer in secDNS, exiting...",
				log.Fields{
					types.LogFieldKeys.Error: err.Error(),
				})
		}
		return err
	}
	return nil
}

// CreateKeyDataSet inserts the KeyDataSet into the database
func (db *database) CreateKeyDataSet(ctx context.Context, keyDataSet []model.TransferInDomainSecdnsKeyDatum) error {
	tx := db.GetDB().WithContext(ctx)
	err := tx.Create(keyDataSet).Error
	if err != nil {
		if errors.Is(err, &pgconn.ConnectError{}) {
			log.Fatal("error inserting domain transfer in keyData, exiting...",
				log.Fields{
					types.LogFieldKeys.Error: err.Error(),
				})
		}
		return err
	}
	return nil
}

// GetHostingStatusName gets name by id; where 'name' is key and 'id' is value
func (db *database) GetHostingStatusName(id string) string {
	return db.hostingStatusEnum.GetByValue(id)
}

// GetHostingStatusId gets id by name; where 'name' is key and 'id' is value
func (db *database) GetHostingStatusId(name string) string {
	return db.hostingStatusEnum.GetByKey(name)
}
