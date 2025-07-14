package handlers

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// RyDomainCheckHandler receives domain check responses from the registry interface
// handles accordingly a job type pointed by message correlation id
func (service *WorkerService) RyDomainCheckHandler(server messagebus.Server, message proto.Message) error {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "RyDomainCheckHandler")
	defer service.tracer.FinishSpan(span)

	correlationId := server.Envelope().CorrelationId

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: correlationId,
	})

	response := message.(*ryinterface.DomainCheckResponse)

	logger.Debug(types.LogMessages.ReceivedResponseFromRY, log.Fields{
		types.LogFieldKeys.Response: response.String(),
	})

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

		logger.Info("Starting response processing for domain check job")

		if job.StatusID != tx.GetJobStatusId(types.JobStatus.Processing) {
			logger.Error(types.LogMessages.UnexpectedJobStatus, log.Fields{
				types.LogFieldKeys.Status: job.Info.JobStatusName,
			})
			return
		}

		err = RyDomainCheckRequestRouter(ctx, response, job, tx, logger)
		if err != nil {
			logger.Error(types.LogMessages.HandleMessageFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

		logger.Info(types.LogMessages.JobProcessingCompleted)

		return
	})
}

// RyDomainCheckRequestRouter routes the domain check request to the appropriate handler
func RyDomainCheckRequestRouter(ctx context.Context, response *ryinterface.DomainCheckResponse, job *model.Job, tx database.Database, logger logger.ILogger) (err error) {
	jobType := *job.Info.JobTypeName

	switch jobType {
	case "validate_domain_claims":
		err = RyValidateDomainClaimsHandler(ctx, response, job, tx, logger)
	case "validate_domain_available", "validate_domain_premium":
		err = RyValidateDomainCheckHandler(ctx, response, job, tx, logger)
	default:
		err = fmt.Errorf("no domain check response handler for job %q", jobType)
	}

	return
}
