package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/google/uuid"
	"golang.org/x/exp/slices"
	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/epp_utils"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// RyDomainDeleteHandler receives the responses from the registry interface
// and updates the database
func (service *WorkerService) RyDomainDeleteHandler(server messagebus.Server, message proto.Message) error {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "RyDomainDeleteHandler")
	defer service.tracer.FinishSpan(span)

	correlationId := server.Envelope().CorrelationId

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: correlationId,
	})

	response := message.(*ryinterface.DomainDeleteResponse)

	logger.Debug(types.LogMessages.ReceivedResponseFromRY, log.Fields{
		types.LogFieldKeys.Response: response.String(),
	})

	data := new(types.DomainDeleteData)

	return service.db.WithTransaction(func(tx database.Database) (err error) {
		job, err := tx.GetJobById(ctx, correlationId, true)
		if err != nil {
			logger.Error(types.LogMessages.FetchJobByIDFromDBFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

		logger = logger.CreateChildLogger(log.Fields{
			types.LogFieldKeys.LogID:   uuid.NewString(),
			types.LogFieldKeys.JobType: *job.Info.JobTypeName,
		})

		logger.Info("Starting response processing for domain delete job")

		if job.StatusID != tx.GetJobStatusId(types.JobStatus.Processing) {
			logger.Warn(types.LogMessages.UnexpectedJobStatus, log.Fields{
				types.LogFieldKeys.Status: job.Info.JobStatusName,
			})
			return
		}

		err = json.Unmarshal(job.Info.Data, data)
		if err != nil {
			logger.Error(types.LogMessages.JSONDecodeFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})

			resMsg := err.Error()
			job.ResultMessage = &resMsg
			err = tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
			if err != nil {
				logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
					types.LogFieldKeys.Error: err,
				})
			}
			return
		}

		registryResponse := response.GetRegistryResponse()

		jrd := types.JobResultData{Message: message}

		if registryResponse.GetIsSuccess() {
			logger.Info("Domain was successfully deleted on the registry backend")

			// Check if the domain is in the redemption grace period
			data, err = service.IsDomainInRedemptionGracePeriod(ctx, tx, registryResponse, data, logger)
			if err != nil {
				logger.Error("Error checking domain RGP status", log.Fields{
					types.LogFieldKeys.Error: err,
				})

				resMsg := "Failed to retrieve the domain RGP status"
				job.ResultMessage = &resMsg
				return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
			}

			// Process the domain delete response
			err = ProcessRyDomainDeleteResponse(ctx, tx, registryResponse, data, job, logger)
			if err != nil {
				logger.Error("Failed to process domain delete response", log.Fields{
					types.LogFieldKeys.Error: err,
				})

				resMsg := err.Error()
				job.ResultMessage = &resMsg
				return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
			}

			// Set the job status to completed
			err = tx.SetJobStatus(ctx, job, types.JobStatus.Completed, &jrd)
			if err != nil {
				logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
					types.LogFieldKeys.Error: err,
				})
				return
			}
		} else if registryResponse.GetEppCode() == types.EppCode.ObjectDoesNotExist {
			// If the domain does not exist, complete the job.
			logger.Info("Domain does not exist in the registry", log.Fields{
				types.LogFieldKeys.Domain: data.Name,
			})

			err = tx.SetJobStatus(ctx, job, types.JobStatus.Completed, &jrd)
			if err != nil {
				logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
					types.LogFieldKeys.Error: err,
				})
				return
			}
		} else {
			logger.Error("Failed to delete domain in registry", log.Fields{
				types.LogFieldKeys.EppCode:     registryResponse.GetEppCode(),
				types.LogFieldKeys.EppMessage:  registryResponse.GetEppMessage(),
				types.LogFieldKeys.XmlResponse: registryResponse.GetXml(),
			})

			epp_utils.SetJobErrorFromRegistryResponse(registryResponse, job, &jrd)
			err = tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
			if err != nil {
				logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
					types.LogFieldKeys.Error: err,
				})
				return
			}
		}

		logger.Info(types.LogMessages.JobProcessingCompleted)

		return
	})
}

// ProcessRyDomainDeleteResponse processes the response from the registry interface for domain delete and updates the database
func ProcessRyDomainDeleteResponse(ctx context.Context, tx database.Database, registryResponse *common.RegistryResponse, data *types.DomainDeleteData, job *model.Job, logger logger.ILogger) (err error) {
	pdd := model.ProvisionDomainDelete{
		ID:                      *job.Info.ReferenceID,
		RyCltrid:                &registryResponse.EppCltrid,
		InRedemptionGracePeriod: data.InRedemptionGracePeriod,
	}

	err = tx.UpdateProvisionDomainDelete(ctx, &pdd)
	if err != nil {
		logger.Error("Failed to update provision data in DB", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	logger.Info("Provision data updated in DB", log.Fields{
		types.LogFieldKeys.Provision: pdd,
	})

	return
}

// IsDomainInRedemptionGracePeriod checks if the domain is in the redemption grace period
func (service *WorkerService) IsDomainInRedemptionGracePeriod(ctx context.Context, tx database.Database, registryResponse *common.RegistryResponse, data *types.DomainDeleteData, logger logger.ILogger) (*types.DomainDeleteData, error) {
	domain, err := tx.GetVDomain(ctx, &model.VDomain{Name: &data.Name, TenantCustomerID: &data.TenantCustomerId})
	if err != nil {
		logger.Error("Error fetching domain from database", log.Fields{
			types.LogFieldKeys.Error: err,
		})

		return data, fmt.Errorf("failed to fetch domain from database")
	}

	if domain.RgpEppStatus == nil || *domain.RgpEppStatus != types.RgpStatus.AddPeriod {
		// domain was not in add grace period therefore must enter redemption grace period after deletion
		data.InRedemptionGracePeriod = true
	} else {
		if registryResponse.GetEppCode() == 1000 {
			// domain was in add grace period prior to deletion, response code states domain is deleted from registry immediately; no redemption grace period
			data.InRedemptionGracePeriod = false
		} else {
			// unexpected response code received for domain delete response
			domainInfoResp, err := service.getDomainInfo(ctx, data.Name, data.Accreditation.AccreditationName)
			if err != nil {
				logger.Error("Unexpected error fetching domain info from registry", log.Fields{
					types.LogFieldKeys.Error: err,
				})

				return data, fmt.Errorf("unexpected error fetching domain info from registry")
			}

			if domainInfoResp.GetRegistryResponse().GetEppCode() == types.EppCode.ObjectDoesNotExist {
				// domain deleted from registry; no redemption grace period
				data.InRedemptionGracePeriod = false
			} else if domainInfoResp.GetRegistryResponse().GetEppCode() == types.EppCode.Success {
				// domain still exists in registry; check domain data
				rgpMsg, err := handleRgpExtension(domainInfoResp.GetExtensions())
				if err != nil {
					logger.Error("Failed to handle RGP extension", log.Fields{
						types.LogFieldKeys.Error: err,
					})

					return data, err
				}

				if rgpMsg.Rgpstatus == types.RgpStatus.RedemptionPeriod {
					data.InRedemptionGracePeriod = true
				} else if slices.Contains(domainInfoResp.GetStatuses(), types.EPPStatusCode.PendingDelete) {
					data.InRedemptionGracePeriod = false
				} else {
					logger.Error("Failed to determine domain status for domain", log.Fields{
						types.LogFieldKeys.Domain: data.Name,
						types.LogFieldKeys.Status: strings.Join(domainInfoResp.GetStatuses(), ", "),
					})

					return data, fmt.Errorf("failed to determine domain status for domain: %s", data.Name)
				}
			} else {
				logger.Error("Failed to fetch domain info from registry", log.Fields{
					types.LogFieldKeys.Domain:      data.Name,
					types.LogFieldKeys.EppCode:     registryResponse.GetEppCode(),
					types.LogFieldKeys.EppMessage:  registryResponse.GetEppMessage(),
					types.LogFieldKeys.XmlResponse: registryResponse.GetXml(),
				})

				return data, fmt.Errorf("failed to fetch domain info from registry")
			}
		}
	}

	return data, nil
}
