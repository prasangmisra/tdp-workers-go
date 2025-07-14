package handlers

import (
	"encoding/json"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// HostingUpdateHandler This is a callback handler for the Hosting update event
// and is in charge of sending the update request to the hosting api on AWS
func (service *WorkerService) HostingUpdateHandler(server messagebus.Server, message proto.Message) error {
	ctx := server.Context()

	request := message.(*job.Notification)
	jobId := request.GetJobId()

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: jobId,
	})

	logger.Info("Starting HostingUpdateHandler for the job")

	data := new(types.HostingUpdateData)

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

		logger.Info("Starting hosting update job processing")

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
			logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

		var response *OrderResponse
		if data.IsActive != nil {
			response, err = service.hostingApi.UpdateHosting(createUpdateOrderRequest(data))
			if err != nil {
				logger.Error("Error updating hosting", log.Fields{
					types.LogFieldKeys.Error: err,
				})
			}

		} else if data.Certificate != nil {
			// certificate update does not return response by design. mimicking setting response status explicitly
			err = service.hostingApi.UpdateHostingCertificate(createUpdateCertificateRequest(data))
			if err != nil {
				logger.Error("Error updating certificates for hosting", log.Fields{
					types.LogFieldKeys.Error: err,
				})
			} else {
				response = &OrderResponse{Status: types.OrderStatusHostingAPI.InProgress}
			}

		} else {
			errMsg := fmt.Sprintf("Invalid update request for hosting %q", data.HostingId)
			logger.Error(errMsg)
			response = &OrderResponse{Status: "Failed"}
			err = errors.New(errMsg)
		}

		if err != nil {
			resMsg := err.Error()
			job.ResultMessage = &resMsg
			return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
		}
		switch response.Status {
		case types.OrderStatusHostingAPI.Completed:
			logger.Info("Hosting successfully updated and completed for job")
		case types.OrderStatusHostingAPI.InProgress:
			logger.Info("Hosting update is in progress for job")
		case types.OrderStatusHostingAPI.Failed:
			logger.Warn("Hosting update reported as failed by API for job")
		default:
			logger.Info("Hosting update processed with unknown status for job", log.Fields{
				"status": response.Status,
			})
		}

		if err = tx.SetProvisionHostingUpdateDetails(ctx, *job.Info.ReferenceID, response.Status); err != nil {
			logger.Error("Error setting provision hosting update details for hosting", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

		logger.Info(types.LogMessages.JobProcessingCompleted)
		return tx.SetJobStatus(ctx, job, types.JobStatus.Completed, nil)
	})

}
