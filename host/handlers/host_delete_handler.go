package handlers

import (
	"encoding/json"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// HostDeleteHandler This is a callback handler for the HostDelete event
// and is in charge of sending the request to the registry interface
func (service *WorkerService) HostDeleteHandler(server messagebus.Server, message proto.Message) error {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "HostDeleteHandler")
	defer service.tracer.FinishSpan(span)

	// we need to type-cast the proto.Message to the wanted type
	request := message.(*job.Notification)
	jobId := request.GetJobId()

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: jobId,
	})

	logger.Info("Starting HostDeleteHandler for the job")

	data := new(types.HostDeleteData)

	return service.db.WithTransaction(func(tx database.Database) (err error) {
		job, err := tx.GetJobById(ctx, jobId, true)
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

		logger.Info("Starting host delete job processing")

		if job.StatusID != tx.GetJobStatusId(types.JobStatus.Submitted) {
			logger.Error(types.LogMessages.UnexpectedJobStatus, log.Fields{
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

		msg, err := toHostDeleteRequest(*data)
		if err != nil {
			logger.Error(types.LogMessages.ParseJobDataToRegistryRequestFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

		queue := types.GetTransformQueue(data.Accreditation.AccreditationName)
		headers := map[string]any{
			"reply_to":       "WorkerJobHostProvisionUpdate",
			"correlation_id": jobId,
		}

		err = server.MessageBus().Send(ctx, queue, msg, headers)
		if err != nil {
			logger.Error(types.LogMessages.MessageSendingToBusFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

		logger.Info(types.LogMessages.MessageSendingToBusSuccess, log.Fields{
			types.LogFieldKeys.Host:                 data.HostName,
			types.LogFieldKeys.MessageCorrelationID: jobId,
		})

		err = tx.SetJobStatus(ctx, job, types.JobStatus.Processing, nil)
		if err != nil {
			logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

		logger.Info(types.LogMessages.UpdateStatusInDBSuccess)

		return
	})
}

// toHostDeleteRequest converts HostDeleteData to ryinterface's HostDeleteRequest
func toHostDeleteRequest(data types.HostDeleteData) (hostDeleteRequest *ryinterface.HostDeleteRequest, err error) {
	hostDeleteRequest = &ryinterface.HostDeleteRequest{
		Name: data.HostName,
	}

	return
}
