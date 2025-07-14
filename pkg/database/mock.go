package database

import (
	"context"

	"gorm.io/gorm"

	"github.com/stretchr/testify/mock"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

type MockDatabase struct {
	mock.Mock
}

func (m *MockDatabase) GetAccreditationById(ctx context.Context, id string) (acc *model.Accreditation, err error) {
	args := m.Called(ctx, id)
	return args.Get(0).(*model.Accreditation), args.Error(1)
}

func (m *MockDatabase) UpdateProvisionDomainTransferInRequest(ctx context.Context, pdtr *model.ProvisionDomainTransferInRequest) error {
	args := m.Called(ctx, pdtr)
	return args.Error(0)
}

func (m *MockDatabase) UpdateProvisionDomainTransferIn(ctx context.Context, pdti *model.ProvisionDomainTransferIn) error {
	args := m.Called(ctx, pdti)
	return args.Error(0)
}

func (m *MockDatabase) GetExpiredPendingProvisionDomainTransferInRequests(ctx context.Context, batchSize int) (result []model.ProvisionDomainTransferInRequest, err error) {
	args := m.Called(ctx, batchSize)
	return args.Get(0).([]model.ProvisionDomainTransferInRequest), args.Error(1)
}

func (m *MockDatabase) GetTransferStatusName(name string) string {
	args := m.Called(name)
	return args.String(0)
}

func (m *MockDatabase) Ping(ctx context.Context) error {
	args := m.Called()
	return args.Error(0)
}

func (m *MockDatabase) GetDB() *gorm.DB {
	args := m.Called()
	return args.Get(0).(*gorm.DB)
}

func (m *MockDatabase) Begin() Database {
	args := m.Called()
	return args.Get(0).(Database)
}

func (m *MockDatabase) Commit() error {
	args := m.Called()
	return args.Error(0)
}

func (m *MockDatabase) Rollback() error {
	args := m.Called()
	return args.Error(0)
}

func (m *MockDatabase) WithTransaction(f func(Database) error) (err error) {
	args := m.Called(f)
	return args.Error(0)
}

func (m *MockDatabase) Close() {
	m.Called()
}

func (m *MockDatabase) GetAccreditationByName(ctx context.Context, name string) (acc *model.Accreditation, err error) {
	args := m.Called(ctx, name)
	return args.Get(0).(*model.Accreditation), args.Error(1)
}

func (m *MockDatabase) GetJobById(ctx context.Context, id string, lock bool) (job *model.Job, err error) {
	args := m.Called(ctx, id, lock)
	return args.Get(0).(*model.Job), args.Error(1)
}

func (m *MockDatabase) GetJobByEventId(ctx context.Context, eventId string, lock bool) (job *model.Job, err error) {
	args := m.Called(ctx, eventId, lock)
	return args.Get(0).(*model.Job), args.Error(1)
}

func (m *MockDatabase) SetJobStatus(ctx context.Context, job *model.Job, status string, jrd *types.JobResultData) error {
	args := m.Called(ctx, job, status, jrd)
	return args.Error(0)
}

func (m *MockDatabase) UpdateJob(ctx context.Context, job *model.Job) error {
	args := m.Called(ctx, job)
	return args.Error(0)
}

func (m *MockDatabase) SetProvisionContactHandle(ctx context.Context, id string, handle string) error {
	args := m.Called(ctx, id, handle)
	return args.Error(0)
}

func (m *MockDatabase) SetProvisionDomainRedeem(ctx context.Context, id string, isRequest *bool, isReport *bool) (err error) {
	args := m.Called(ctx, id, isRequest, isReport)
	return args.Error(0)
}

func (m *MockDatabase) GetProvisionDomainRedeem(ctx context.Context, id string) (prd *model.ProvisionDomainRedeem, err error) {
	args := m.Called(ctx, id)
	return args.Get(0).(*model.ProvisionDomainRedeem), args.Error(1)
}

func (m *MockDatabase) GetProvisionDomainRenew(ctx context.Context, id string) (pdr *model.ProvisionDomainRenew, err error) {
	args := m.Called(ctx, id)
	return args.Get(0).(*model.ProvisionDomainRenew), args.Error(1)
}

func (m *MockDatabase) GetProvisionDomainDelete(ctx context.Context, id string) (pdr *model.ProvisionDomainDelete, err error) {
	args := m.Called(ctx, id)
	return args.Get(0).(*model.ProvisionDomainDelete), args.Error(1)
}

func (m *MockDatabase) GetProvisionDomain(ctx context.Context, id string) (pd *model.ProvisionDomain, err error) {
	args := m.Called(ctx, id)
	return args.Get(0).(*model.ProvisionDomain), args.Error(1)
}

func (m *MockDatabase) GetProvisionDomainTransferIn(ctx context.Context, id string) (pdti *model.ProvisionDomainTransferIn, err error) {
	args := m.Called(ctx, id)
	return args.Get(0).(*model.ProvisionDomainTransferIn), args.Error(1)
}

func (m *MockDatabase) GetDomain(ctx context.Context, domain *model.Domain) (result *model.Domain, err error) {
	args := m.Called(ctx, domain)
	return args.Get(0).(*model.Domain), args.Error(1)
}

func (m *MockDatabase) GetVDomain(ctx context.Context, domain *model.VDomain) (result *model.VDomain, err error) {
	args := m.Called(ctx, domain)
	return args.Get(0).(*model.VDomain), args.Error(1)
}

func (m *MockDatabase) UpdateDomain(ctx context.Context, domain *model.Domain) (err error) {
	args := m.Called(ctx, domain)
	return args.Error(0)
}

func (m *MockDatabase) UpdateProvisionDomain(ctx context.Context, pd *model.ProvisionDomain) error {
	args := m.Called(ctx, pd)
	return args.Error(0)
}

func (m *MockDatabase) UpdateProvisionDomainUpdate(ctx context.Context, pdu *model.ProvisionDomainUpdate) error {
	args := m.Called(ctx, pdu)
	return args.Error(0)
}

func (m *MockDatabase) UpdateProvisionDomainDelete(ctx context.Context, pdd *model.ProvisionDomainDelete) error {
	args := m.Called(ctx, pdd)
	return args.Error(0)
}

func (m *MockDatabase) UpdateProvisionDomainRenew(ctx context.Context, pdrn *model.ProvisionDomainRenew) error {
	args := m.Called(ctx, pdrn)
	return args.Error(0)
}

func (m *MockDatabase) UpdateProvisionDomainRedeem(ctx context.Context, pdrd *model.ProvisionDomainRedeem) error {
	args := m.Called(ctx, pdrd)
	return args.Error(0)
}

func (m *MockDatabase) CreateDomainRgpStatus(ctx context.Context, drs *model.DomainRgpStatus) (err error) {
	args := m.Called(ctx, drs)
	return args.Error(0)
}

func (m *MockDatabase) GetProvisionDomainTransferInRequest(ctx context.Context, domain *model.ProvisionDomainTransferInRequest) (*model.ProvisionDomainTransferInRequest, error) {
	args := m.Called(ctx, domain)
	return args.Get(0).(*model.ProvisionDomainTransferInRequest), args.Error(1)
}

func (m *MockDatabase) UpdateProvisionHostingCreate(ctx context.Context, upd *model.ProvisionHostingCreate, cond interface{}) error {
	args := m.Called(ctx, upd, cond)
	return args.Error(0)
}

func (m *MockDatabase) SetProvisionHostingUpdateDetails(ctx context.Context, id string, status string) (err error) {
	args := m.Called(ctx, id, status)
	return args.Error(0)
}

func (m *MockDatabase) SetProvisionHostingDeleteDetails(ctx context.Context, id string, status string, isDeleted bool) (err error) {
	args := m.Called(ctx, id, status, isDeleted)
	return args.Error(0)
}

func (m *MockDatabase) GetVProvisionDomain(ctx context.Context, pd *model.VProvisionDomain) (result *model.VProvisionDomain, err error) {
	args := m.Called(ctx, pd)
	return args.Get(0).(*model.VProvisionDomain), args.Error(1)
}

func (m *MockDatabase) SetProvisionDomainStatus(ctx context.Context, id string, status string) (err error) {
	args := m.Called(ctx, id, status)
	return args.Error(0)
}

func (m *MockDatabase) GetHosting(ctx context.Context, hosting *model.Hosting) (result *model.Hosting, err error) {
	args := m.Called(ctx, hosting)
	return args.Get(0).(*model.Hosting), args.Error(1)
}

func (m *MockDatabase) UpdateHosting(ctx context.Context, hosting *model.Hosting) (err error) {
	args := m.Called(ctx, hosting)
	return args.Error(0)
}

func (m *MockDatabase) GetProvisionHostingCertififcate(ctx context.Context, provisionCertificate *model.ProvisionHostingCertificateCreate) (result *model.ProvisionHostingCertificateCreate, err error) {
	args := m.Called(ctx, provisionCertificate)
	return args.Get(0).(*model.ProvisionHostingCertificateCreate), args.Error(1)
}

func (m *MockDatabase) UpdateProvisionHostingCertificate(ctx context.Context, provisionCertificate *model.ProvisionHostingCertificateCreate) (err error) {
	args := m.Called(ctx, provisionCertificate)
	return args.Error(0)
}

func (m *MockDatabase) GetJobStatusId(name string) string {
	args := m.Called(name)
	return args.String(0)
}

func (m *MockDatabase) GetJobStatusName(id string) string {
	args := m.Called(id)
	return args.String(0)
}

func (m *MockDatabase) GetJobTypeName(id string) string {
	args := m.Called(id)
	return args.String(0)
}

func (m *MockDatabase) GetProvisionStatusId(name string) string {
	args := m.Called(name)
	return args.String(0)
}

func (m *MockDatabase) GetProvisionStatusName(id string) string {
	args := m.Called(id)
	return args.String(0)
}

func (m *MockDatabase) GetDomainContactTypeName(id string) string {
	args := m.Called(id)
	return args.String(0)
}

func (m *MockDatabase) GetDomainContactTypeId(name string) string {
	args := m.Called(name)
	return args.String(0)
}

func (m *MockDatabase) GetPollMessageTypeId(name string) string {
	args := m.Called(name)
	return args.String(0)
}

func (m *MockDatabase) GetPollMessageTypeName(id string) string {
	args := m.Called(id)
	return args.String(0)
}

func (m *MockDatabase) GetPollMessageStatusName(id string) string {
	args := m.Called(id)
	return args.String(0)
}

func (m *MockDatabase) GetPollMessageStatusId(name string) string {
	args := m.Called(name)
	return args.String(0)
}

func (m *MockDatabase) GetRgpStatusId(name string) string {
	args := m.Called(name)
	return args.String(0)
}

func (m *MockDatabase) GetTLDSetting(ctx context.Context, accreditationTldID string, key string) (attribute *model.VAttribute, err error) {
	args := m.Called(ctx, accreditationTldID, key)
	return args.Get(0).(*model.VAttribute), args.Error(1)
}

func (m *MockDatabase) CreatePollMessage(ctx context.Context, message *model.PollMessage) (err error) {
	args := m.Called(ctx, message)
	return args.Error(0)
}

func (m *MockDatabase) UpdatePollMessageStatus(ctx context.Context, messageId string, status string) error {
	args := m.Called(ctx, messageId, status)
	return args.Error(0)
}

func (m *MockDatabase) GetHost(ctx context.Context, host *model.Host) (result *model.Host, err error) {
	args := m.Called(ctx, host)
	return args.Get(0).(*model.Host), args.Error(1)
}

func (m *MockDatabase) GetStaleJobs(ctx context.Context) ([]model.StaleJob, error) {
	args := m.Called(ctx)
	return args.Get(0).([]model.StaleJob), args.Error(1)
}

func (m *MockDatabase) GetTransferStatusId(name string) string {
	args := m.Called(name)
	return args.String(0)
}

func (m *MockDatabase) GetOrderItemPlanStatusId(name string) string {
	args := m.Called(name)
	return args.String(0)
}

func (m *MockDatabase) GetOrderItemPlanStatusName(id string) string {
	args := m.Called(id)
	return args.String(0)
}

func (m *MockDatabase) GetOrderItemPlanValidationStatusId(name string) string {
	args := m.Called(name)
	return args.String(0)
}

func (m *MockDatabase) GetOrderItemPlanValidationStatusName(id string) string {
	args := m.Called(id)
	return args.String(0)
}

func (m *MockDatabase) UpdateOrderItemPlan(ctx context.Context, pd *model.OrderItemPlan) error {
	args := m.Called(ctx, pd)
	return args.Error(0)
}

func (m *MockDatabase) TransferAwayDomainOrder(ctx context.Context, order *model.Order) (err error) {
	args := m.Called(ctx, order)
	err = args.Error(0)
	return
}

func (m *MockDatabase) GetOrderTypeId(name string, productName string) (id string) {
	args := m.Called(name, productName)
	if args.Get(0) != nil {
		id = args.Get(0).(string)
	}

	return
}

func (m *MockDatabase) GetOrderTypeName(id string) (name string, productName string) {
	args := m.Called(id)
	if args.Get(0) != nil {
		name = args.Get(0).(string)
	}

	if args.Get(1) != nil {
		productName = args.Get(1).(string)
	}

	return
}

func (m *MockDatabase) OrderNextStatus(ctx context.Context, orderId string, isSuccess bool) (err error) {
	args := m.Called(ctx, orderId, isSuccess)
	err = args.Error(0)
	return
}

func (m *MockDatabase) GetTransferAwayOrder(ctx context.Context, orderStatus, domainName, tenantID string) (result *model.OrderItemTransferAwayDomain, err error) {
	args := m.Called(ctx, orderStatus, domainName, tenantID)
	return args.Get(0).(*model.OrderItemTransferAwayDomain), args.Error(1)
}

func (m *MockDatabase) UpdateTransferAwayDomain(ctx context.Context, ota *model.OrderItemTransferAwayDomain) (err error) {
	args := m.Called(ctx, ota)
	return args.Error(0)
}

func (m *MockDatabase) GetDomainAccreditation(ctx context.Context, domainName string) (*model.DomainWithAccreditation, error) {
	args := m.Called(ctx, domainName)
	return args.Get(0).(*model.DomainWithAccreditation), args.Error(1)
}

func (m *MockDatabase) GetActionableTransferAwayOrders(ctx context.Context, batchSize int) (result []model.VOrderTransferAwayDomain, err error) {
	args := m.Called(ctx, batchSize)
	return args.Get(0).([]model.VOrderTransferAwayDomain), args.Error(1)
}

func (m *MockDatabase) GetOrderItemCreateDomain(ctx context.Context, orderItemId string) (result *model.OrderItemCreateDomain, err error) {
	args := m.Called(ctx, orderItemId)
	return args.Get(0).(*model.OrderItemCreateDomain), args.Error(1)
}

func (m *MockDatabase) UpdateOrderItemCreateDomain(ctx context.Context, ocd *model.OrderItemCreateDomain) (err error) {
	args := m.Called(ctx, ocd)
	return args.Error(0)
}

func (m *MockDatabase) CreateOrder(ctx context.Context, order *model.Order) (err error) {
	args := m.Called(ctx, order)
	err = args.Error(0)
	return
}

func (m *MockDatabase) GetPurgeableDomains(ctx context.Context, batchSize int) (domains []model.VDomain, err error) {
	args := m.Called(ctx, batchSize)
	return args.Get(0).([]model.VDomain), args.Error(1)
}

func (m *MockDatabase) DeleteDomainWithReason(ctx context.Context, domainId string, reason string) (err error) {
	args := m.Called(ctx, domainId, reason)
	err = args.Error(0)
	return
}

func (m *MockDatabase) CreateDsDataSet(ctx context.Context, dsDataSet []model.TransferInDomainSecdnsDsDatum) error {
	args := m.Called(ctx, dsDataSet)
	return args.Error(0)
}

func (m *MockDatabase) CreateKeyDataSet(ctx context.Context, keyDataSet []model.TransferInDomainSecdnsKeyDatum) error {
	args := m.Called(ctx, keyDataSet)
	return args.Error(0)
}

func (m *MockDatabase) GetHostingStatusName(id string) (name string) {
	args := m.Called(id)
	if args.Get(0) != nil {
		name = args.Get(0).(string)
	}

	return
}

func (m *MockDatabase) GetHostingStatusId(name string) (id string) {
	args := m.Called(name)
	if args.Get(0) != nil {
		id = args.Get(0).(string)
	}

	return
}
