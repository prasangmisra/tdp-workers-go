package handlers

import (
	"encoding/json"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	commonmessages "github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

const ExpiryDateFormat = "2006-01-02"

// DomainRenewHandler This is a callback handler for the DomainRenew event
// and is in charge of sending the request to the registry interface
func (service *WorkerService) DomainRenewHandler(server messagebus.Server, message proto.Message) error {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "DomainRenewHandler")
	defer service.tracer.FinishSpan(span)

	// we need to type-cast the proto.Message to the wanted type
	request := message.(*job.Notification)
	jobId := request.GetJobId()

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: jobId,
	})

	logger.Info("Started DomainRenewHandler for the job")

	data := new(types.DomainRenewData)

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

		logger.Info("Starting domain renew job processing")

		if job.StatusID != tx.GetJobStatusId(types.JobStatus.Submitted) {
			logger.Warn(types.LogMessages.UnexpectedJobStatus, log.Fields{
				types.LogFieldKeys.Status: job.Info.JobStatusName,
			})
			return
		}

		// get the updated provision data (period and current expiry date)
		provisionData, err := tx.GetProvisionDomainRenew(ctx, *job.Info.ReferenceID)
		if err != nil {
			logger.Error("Failed to get provision data", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

		// if the period is 0, no renew is required
		if *provisionData.Period == 0 {
			logger.Info("No renew is required", log.Fields{
				types.LogFieldKeys.Domain: data.Name,
				"current_expiry_date":     provisionData.CurrentExpiryDate.Format(ExpiryDateFormat),
				"ry_expiry_date":          provisionData.RyExpiryDate.Format(ExpiryDateFormat),
			})

			err = tx.SetJobStatus(ctx, job, types.JobStatus.Completed, nil)
			if err != nil {
				logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{types.LogFieldKeys.Error: err})
			}
			logger.Info(types.LogMessages.UpdateStatusInDBSuccess)

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

		msg := ryinterface.DomainRenewRequest{
			Name:              data.Name,
			Period:            uint32(*provisionData.Period),
			PeriodUnit:        commonmessages.PeriodUnit_YEAR,
			CurrentExpiryDate: timestamppb.New(provisionData.CurrentExpiryDate),
		}

		if data.Price != nil {
			var anyFee *anypb.Any
			feeExtension := &extension.FeeTransformRequest{Fee: []*extension.FeeFee{{Price: types.ToMoneyMsg(data.Price)}}}
			anyFee, err = anypb.New(feeExtension)
			if err != nil {
				logger.Error("Failed to create fee extension", log.Fields{
					types.LogFieldKeys.Error: err,
				})
				return
			}
			msg.Extensions = map[string]*anypb.Any{"fee": anyFee}
			logger.Debug("Added fee extension to the renew request")
		}

		queue := types.GetTransformQueue(data.Accreditation.AccreditationName)
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
			"expiry_date":                           provisionData.CurrentExpiryDate.Format(ExpiryDateFormat),
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
