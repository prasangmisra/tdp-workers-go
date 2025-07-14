package handlers

import (
	"context"
	"encoding/json"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"

	// import required to parse domain create response
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/epp_utils"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// RyDomainProvisionHandler receives the responses from the registry interface
// and updates the database
func (service *WorkerService) RyDomainProvisionHandler(server messagebus.Server, message proto.Message) error {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "RyDomainProvisionHandler")
	defer service.tracer.FinishSpan(span)

	correlationId := server.Envelope().CorrelationId

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: correlationId,
	})

	response := message.(*ryinterface.DomainCreateResponse)

	logger.Debug(types.LogMessages.ReceivedResponseFromRY, log.Fields{
		types.LogFieldKeys.Response: response.String(),
	})

	data := new(types.DomainData)

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

		logger.Info("Starting response processing for domain create job")

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
			logger.Info("Domain successfully provisioned on registry backend", log.Fields{
				types.LogFieldKeys.Domain: data.Name,
			})

			// Process the domain provision response
			err = ProcessRyDomainProvisionResponse(ctx, response, job, tx, logger)
			if err != nil {
				logger.Error("Failed to process domain provision response", log.Fields{
					types.LogFieldKeys.Error: err,
				})

				resMsg := err.Error()
				job.ResultMessage = &resMsg
				return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
			}

			if registryResponse.EppCode == types.EppCode.Pending {
				logger.Info("Domain provision completed conditionally", log.Fields{
					types.LogFieldKeys.Domain: data.Name,
				})

				return tx.SetJobStatus(ctx, job, types.JobStatus.CompletedConditionally, &jrd)
			}

			err = tx.SetJobStatus(ctx, job, types.JobStatus.Completed, &jrd)
			if err != nil {
				logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
					types.LogFieldKeys.Error: err,
				})
				return
			}
		} else {
			logger.Error("Failed to provision domain in registry", log.Fields{
				types.LogFieldKeys.Domain:      data.Name,
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

// ProcessRyDomainProvisionResponse processes the domain provisioning response and updates the database
func ProcessRyDomainProvisionResponse(ctx context.Context, response *ryinterface.DomainCreateResponse, job *model.Job, tx database.Database, logger logger.ILogger) (err error) {
	pd := model.ProvisionDomain{
		ID:            *job.Info.ReferenceID,
		RyCltrid:      &response.RegistryResponse.EppCltrid,
		RyCreatedDate: types.TimestampToTime(response.GetCreatedDate()),
		RyExpiryDate:  types.TimestampToTime(response.GetExpiryDate()),
	}

	err = tx.UpdateProvisionDomain(ctx, &pd)
	if err != nil {
		logger.Error("Failed to update provision data in DB", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	logger.Info("Provision data updated in DB", log.Fields{
		types.LogFieldKeys.Provision: pd,
	})

	return
}
