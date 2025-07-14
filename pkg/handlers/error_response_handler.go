package handlers

import (
	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	tcwire "github.com/tucowsinc/tdp-messages-go/message"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

func ErrorResponseHandler(db database.Database) func(server messagebus.Server, message proto.Message) (err error) {
	return func(server messagebus.Server, message proto.Message) (err error) {
		ctx := server.Context()
		correlationId := server.Envelope().CorrelationId

		logger := log.CreateChildLogger(log.Fields{
			types.LogFieldKeys.CorrelationID: correlationId,
		})

		response := message.(*tcwire.ErrorResponse)

		logger.Debug("Received error response from RY interface", log.Fields{
			types.LogFieldKeys.Response: response.GetMessage(),
		})

		job, err := db.GetJobById(ctx, correlationId, true)
		if err != nil {
			logger.Error(types.LogMessages.FetchJobByEventIDFromDBFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

		var jobErr string
		switch *job.Info.JobTypeName {
		case "validate_host_available":
			// Create an OrderItemPlan with the job's reference ID and set its statuses to Failed
			oip := &model.OrderItemPlan{
				ID:                 *job.Info.ReferenceID,
				ValidationStatusID: db.GetOrderItemPlanValidationStatusId(types.OrderItemPlanValidationStatus.Failed),
				ResultMessage:      &response.Message,
			}

			// Update the order item plan with job status
			err = db.UpdateOrderItemPlan(ctx, oip)
			if err != nil {
				logger.Error("Error updating order item plan", log.Fields{
					types.LogFieldKeys.Error: err,
				})

				resMsg := err.Error()
				job.ResultMessage = &resMsg
				return db.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
			}

			jobErr = "Failed to validate host availability"
		default:
			// For other job types, we just set the error message in the job
			jobErr = types.LogMessages.HandleMessageFailed
		}

		logger.Error(jobErr)
		job.ResultMessage = &jobErr
		err = db.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
		if err != nil {
			logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
		} else {
			logger.Info(types.LogMessages.UpdateStatusInDBSuccess, log.Fields{
				types.LogFieldKeys.JobID:  job.ID,
				types.LogFieldKeys.Status: types.JobStatus.Failed,
			})
		}

		return
	}
}
