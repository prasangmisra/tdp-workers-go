package handlers

import (
	"encoding/json"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// DomainRedeemHandler This is a callback handler for the DomainRedeem event
// and is in charge of sending the request to the registry interface
func (service *WorkerService) DomainRedeemHandler(server messagebus.Server, message proto.Message) error {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "DomainRedeemHandler")
	defer service.tracer.FinishSpan(span)

	// we need to type-cast the proto.Message to the wanted type
	request := message.(*job.Notification)
	jobId := request.GetJobId()

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: jobId,
	})

	logger.Debug("Starting DomainRedeemHandler for the job")

	data := new(types.DomainRedeemData)

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

		logger.Info("Starting domain redeem job processing")

		if job.StatusID != tx.GetJobStatusId(types.JobStatus.Submitted) {
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

		// If the domain RGP status is pending restore, don't send the request to the registry
		// and set the job status to completed
		pdr, err := tx.GetProvisionDomainRedeem(ctx, data.ProvisionDomainRedeemId)
		if err != nil {
			logger.Error("Failed to get provision data from DB", log.Fields{
				types.LogFieldKeys.Error: err,
			})

			resMsg := err.Error()
			job.ResultMessage = &resMsg
			return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
		}

		if pdr.InRestorePendingStatus != nil && *pdr.InRestorePendingStatus {
			logger.Info("Domain is in pending restore status", log.Fields{
				types.LogFieldKeys.Domain: data.Name,
			})

			return tx.SetJobStatus(ctx, job, types.JobStatus.Completed, nil)
		}

		msg, err := toDomainRedeemRequest(*data, logger)
		if err != nil {
			logger.Error(types.LogMessages.ParseJobDataToRegistryRequestFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
			resMsg := err.Error()
			job.ResultMessage = &resMsg
			return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
		}

		queue := types.GetTransformQueue(data.Accreditation.AccreditationName)
		headers := map[string]any{
			"reply_to":       "WorkerJobDomainProvisionUpdate",
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
			types.LogFieldKeys.Domain:               data.Name,
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

func toDomainRedeemRequest(data types.DomainRedeemData, logger logger.ILogger) (msg *ryinterface.DomainUpdateRequest, err error) {
	rgpExtension, err := anypb.New(&extension.RgpUpdateRequest{RgpOp: "request"})
	if err != nil {
		logger.Error("Failed to create RGP extension", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return nil, err
	}

	msg = &ryinterface.DomainUpdateRequest{
		Name:       data.Name,
		Extensions: map[string]*anypb.Any{"rgp": rgpExtension},
	}

	// if the price is set, we need to add the fee extension
	if data.Price != nil {
		feeExtension, err := anypb.New(&extension.FeeTransformRequest{Fee: []*extension.FeeFee{{Price: types.ToMoneyMsg(data.Price)}}})
		if err != nil {
			logger.Error("Failed to create Fee extension", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return nil, err
		}
		msg.Extensions["fee"] = feeExtension
	}

	logger.Info("Domain redeem request created successfully")

	return msg, nil
}
