package handlers

import (
	"encoding/json"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// HostingDeleteHandler This is a callback handler for the Hosting delete event
// and is in charge of sending the delete request to the hosting api on AWS
func (service *WorkerService) HostingDeleteHandler(server messagebus.Server, message proto.Message) error {
	ctx := server.Context()

	request := message.(*job.Notification)
	jobId := request.GetJobId()

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: jobId,
	})

	logger.Info("Starting HostingDeleteHandler for the job")

	data := new(types.HostingDeleteData)

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

		logger.Info("Starting hosting delete job processing")

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

		logger = log.CreateChildLogger(log.Fields{types.LogFieldKeys.Metadata: data.Metadata})

		err = tx.SetJobStatus(ctx, job, types.JobStatus.Processing, nil)
		if err != nil {
			// job will be scheduled again by job scheduler
			logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

		response, err := service.hostingApi.DeleteHosting(createDeleteOrderRequest(data))
		if err != nil {
			logger.Error("Error deleting hosting", log.Fields{
				types.LogFieldKeys.Error: err,
			})

			resMsg := err.Error()
			job.ResultMessage = &resMsg
			return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
		}

		if err = tx.SetProvisionHostingDeleteDetails(ctx, *job.Info.ReferenceID, response.Status, response.IsDeleted); err != nil {
			logger.Error("Error updating provision hosting delete details for hosting", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

		return tx.SetJobStatus(ctx, job, types.JobStatus.Completed, nil)
	})

}
