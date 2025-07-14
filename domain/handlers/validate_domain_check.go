package handlers

import (
	"encoding/json"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	commonmessages "github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// ValidateDomainCheckHandler This is a callback handler for the validate domain job
// and is in charge of sending the domain check request to the registry interface
func (service *WorkerService) ValidateDomainCheckHandler(server messagebus.Server, message proto.Message) error {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "ValidateDomainCheckHandler")
	defer service.tracer.FinishSpan(span)

	// we need to type-cast the proto.Message to the wanted type
	request := message.(*job.Notification)
	jobId := request.GetJobId()

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: jobId,
	})

	logger.Debug("Starting ValidateDomainCheckHandler for the job")

	data := new(types.DomainCheckValidationData)

	return service.db.WithTransaction(func(tx database.Database) (err error) {
		job, err := tx.GetJobById(ctx, jobId, true)
		if err != nil {
			logger.Error(types.LogMessages.FetchJobByIDFromDBFailed, log.Fields{types.LogFieldKeys.Error: err})
			return
		}

		logger = logger.CreateChildLogger(log.Fields{
			types.LogFieldKeys.LogID:   uuid.NewString(),
			types.LogFieldKeys.JobType: *job.Info.JobTypeName,
		})

		logger.Info("Starting validate domain check job processing")

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

		logger.Info("Validated job data for domain check")

		msg := ryinterface.DomainCheckRequest{
			Names: []string{data.Name},
		}

		if data.Price != nil {
			err = addFeeExtension(data, &msg)
			if err != nil {
				logger.Error(types.LogMessages.ParseJobDataToRegistryRequestFailed, log.Fields{types.LogFieldKeys.Error: err})
				resMsg := err.Error()
				job.ResultMessage = &resMsg
				err = tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
				if err != nil {
					logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{types.LogFieldKeys.Error: err})
				}
				return
			}
		}

		queue := types.GetQueryQueue(data.Accreditation.AccreditationName)
		headers := map[string]any{
			"reply_to":       "WorkerJobDomainProvisionUpdate",
			"correlation_id": jobId,
		}

		err = server.MessageBus().Send(ctx, queue, &msg, headers)
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

// addFeeExtension adds the fee extension to the domain check request
func addFeeExtension(data *types.DomainCheckValidationData, msg *ryinterface.DomainCheckRequest) (err error) {
	var op ryinterface.DomainOperationFee_BaseOperation

	switch data.OrderType {
	case types.DomainOrderType.TransferIn:
		op = ryinterface.DomainOperationFee_TRANSFER
	case types.DomainOrderType.Renew:
		op = ryinterface.DomainOperationFee_RENEWAL
	case types.DomainOrderType.Redeem:
		op = ryinterface.DomainOperationFee_RESTORE
	case types.DomainOrderType.Create:
		op = ryinterface.DomainOperationFee_REGISTRATION
	}

	feeCheckRequest := &extension.FeeCheckRequest{
		Names:     []string{data.Name},
		Operation: &op,
	}

	if data.Period != nil {
		periodUnit := commonmessages.PeriodUnit_YEAR
		feeCheckRequest.Period = data.Period
		feeCheckRequest.PeriodUnit = &periodUnit
	}

	if data.Price != nil {
		feeCheckRequest.Currency = &data.Price.Currency
	}

	feeExtension, err := anypb.New(
		feeCheckRequest,
	)

	msg.Extensions = map[string]*anypb.Any{"fee": feeExtension}

	return
}
