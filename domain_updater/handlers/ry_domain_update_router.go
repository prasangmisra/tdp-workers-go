package handlers

import (
	"fmt"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/reflect/protoreflect"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

func (service *WorkerService) RyDomainUpdateRouter(server messagebus.Server, message proto.Message) (err error) {
	ctx := server.Context()
	correlationId := server.Envelope().CorrelationId

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: correlationId,
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

		logger.Info("Starting response processing for domain update job")

		if job.StatusID != tx.GetJobStatusId(types.JobStatus.Processing) {
			logger.Error(types.LogMessages.UnexpectedJobStatus, log.Fields{
				types.LogFieldKeys.Status: job.Info.JobStatusName,
			})
			return
		}

		err = service.RyDomainUpdateRequestRouter(server, message, job, tx, logger)
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

// RyDomainUpdateRequestRouter routes the domain update request to the appropriate handler
func (service *WorkerService) RyDomainUpdateRequestRouter(server messagebus.Server, message protoreflect.ProtoMessage, job *model.Job, tx database.Database, logger logger.ILogger) (err error) {
	jobType := *job.Info.JobTypeName

	switch jobType {
	case "provision_domain_redeem", "provision_domain_redeem_report":
		err = service.RyDomainRedeemHandler(server, message, job, tx, logger)
	case "provision_domain_update":
		err = service.RyDomainUpdateHandler(server, message, job, tx, logger)
	default:
		err = fmt.Errorf("no handlers for type: %s", jobType)
	}

	return
}
