package handlers

import (
	"encoding/json"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/epp_utils"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// HostRyResponseHandler receives the responses from the registry interface
// and updates the database
func (service *WorkerService) RyHostProvisionHandler(server messagebus.Server, message proto.Message) error {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "RyHostProvisionHandler")
	defer service.tracer.FinishSpan(span)

	correlationId := server.Envelope().CorrelationId

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: correlationId,
	})

	response := message.(*ryinterface.HostCreateResponse)

	logger.Debug(types.LogMessages.ReceivedResponseFromRY, log.Fields{
		types.LogFieldKeys.Response: response.String(),
	})

	data := new(types.HostData)

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

		logger.Info("Starting response processing for host provision job")

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
			logger.Info("Host was successfully created on the registry backend", log.Fields{
				types.LogFieldKeys.Host: data.HostName,
			})

			err = tx.SetJobStatus(ctx, job, types.JobStatus.Completed, &jrd)
			if err != nil {
				logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
					types.LogFieldKeys.Error: err,
				})
				return
			}
		} else if registryResponse.GetEppCode() == types.EppCode.Exists {
			// when the object already exists (EPP code 2302) we can assume it's already provisioned.
			logger.Info("Host already exists, treating as success", log.Fields{
				types.LogFieldKeys.Host: data.HostName,
			})

			err = tx.SetJobStatus(ctx, job, types.JobStatus.Completed, &jrd)
			if err != nil {
				logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
					types.LogFieldKeys.Error: err,
				})
				return
			}
		} else {
			logger.Error("Failed to provision host in registry", log.Fields{
				types.LogFieldKeys.Host:        data.HostName,
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
