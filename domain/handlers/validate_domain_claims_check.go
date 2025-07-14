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
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// ValidateDomainClaimsCheckHandler This is a callback handler for the validate domain claims job
// and is in charge of sending the domain check request with claims extension to the registry interface
func (service *WorkerService) ValidateDomainClaimsCheckHandler(server messagebus.Server, message proto.Message) error {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "ValidateDomainClaimsCheckHandler")
	defer service.tracer.FinishSpan(span)

	// we need to type-cast the proto.Message to the wanted type
	request := message.(*job.Notification)
	jobId := request.GetJobId()

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: jobId,
	})

	logger.Debug("Starting ValidateDomainClaimsCheckHandler for the job")

	data := new(types.DomainClaimsValidationData)

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

		logger.Info("Starting validate domain claims check job processing")

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

		logger.Info("Validated job data for domain claims check")

		p := extension.LaunchPhase_CLAIMS
		launchCheckRequest := &extension.LaunchCheckRequest{
			Type:  extension.LaunchCheckType_LCHK_CLAIMS,
			Phase: &p,
		}

		launchExtension, err := anypb.New(launchCheckRequest)
		if err != nil {
			logger.Error("Failed to create launch extension", log.Fields{types.LogFieldKeys.Error: err})
			return
		}

		msg := ryinterface.DomainCheckRequest{
			Names:      []string{data.Name},
			Extensions: map[string]*anypb.Any{"launch": launchExtension},
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
