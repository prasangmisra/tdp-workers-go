package handlers

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/epp_utils"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// RyHostDeleteHandler receives the responses from the registry interface
// and deletes the database
func (service *WorkerService) RyHostDeleteHandler(server messagebus.Server, message proto.Message) error {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "RyHostDeleteHandler")
	defer service.tracer.FinishSpan(span)

	correlationId := server.Envelope().CorrelationId

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: correlationId,
	})

	response := message.(*ryinterface.HostDeleteResponse)

	logger.Debug(types.LogMessages.ReceivedResponseFromRY, log.Fields{
		types.LogFieldKeys.Response: response.String(),
	})

	data := new(types.HostDeleteData)

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

		logger.Info("Starting response processing for host delete job")

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
			logger.Info("Host deleted successfully on the registry backend", log.Fields{
				types.LogFieldKeys.Host: data.HostName,
			})

			err = tx.SetJobStatus(ctx, job, types.JobStatus.Completed, &jrd)
			if err != nil {
				logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
					types.LogFieldKeys.Error: err,
				})
				return
			}
		} else if registryResponse.EppCode == types.EppCode.ObjectDoesNotExist {
			logger.Info("Host doesn't exist, treating as success", log.Fields{
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
			if data.HostDeleteRenameAllowed {
				logger.Info("Host not deleted; renaming host instead", log.Fields{
					types.LogFieldKeys.Host: data.HostName,
				})

				err = RyRenameHost(ctx, server.MessageBus(), tx, data, job, jrd, logger)
				if err != nil {
					logger.Error("Error renaming host", log.Fields{
						types.LogFieldKeys.Error: err,
					})

					resMsg := "Failed to delete and rename host in registry"
					job.ResultMessage = &resMsg
					return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
				}
			} else {
				logger.Error("Cannot delete host", log.Fields{
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
		}

		logger.Info(types.LogMessages.JobProcessingCompleted)

		return
	})
}

// RyRenameHost renames the host in the registry
func RyRenameHost(ctx context.Context, bus messagebus.MessageBus, tx database.Database, data *types.HostDeleteData, job *model.Job, jrd types.JobResultData, logger logger.ILogger) error {
	if data.HostDeleteRenameDomain == "" {
		return fmt.Errorf("cannot rename host, delete rename domain name is empty")
	}

	// rename the host
	msg := &ryinterface.HostUpdateRequest{
		Name:    data.HostName,
		NewName: fmt.Sprintf("%s.%s", data.HostName, data.HostDeleteRenameDomain),
	}

	queue := types.GetTransformQueue(data.Accreditation.AccreditationName)
	headers := map[string]any{
		"reply_to":       "WorkerJobHostProvisionUpdate",
		"correlation_id": job.ID,
	}

	err := bus.Send(ctx, queue, msg, headers)
	if err != nil {
		logger.Error("Error sending rename message for job", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return err
	}

	log.Info("Request to rename host was sent", log.Fields{
		types.LogFieldKeys.Host:                 data.HostName,
		types.LogFieldKeys.MessageCorrelationID: job.ID,
	})

	return tx.UpdateJob(ctx, job)
}
