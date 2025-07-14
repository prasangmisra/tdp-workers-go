package handlers

import (
	"context"
	"encoding/json"
	"github.com/google/uuid"
	"golang.org/x/exp/slices"
	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// HostUpdateHandler This is a callback handler for the HostUpdate event
// and is in charge of sending the request to the registry interface
func (service *WorkerService) HostUpdateHandler(server messagebus.Server, message proto.Message) error {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "HostUpdateHandler")
	defer service.tracer.FinishSpan(span)

	// we need to type-cast the proto.Message to the wanted type
	request := message.(*job.Notification)
	jobId := request.GetJobId()

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: jobId,
	})

	logger.Info("Starting HostUpdateHandler for the job")

	data := new(types.HostUpdateData)

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

		logger.Info("Starting host update job processing")

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

		msg, err := toHostUpdateRequest(ctx, service, *data)
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

// toHostUpdateRequest compares the current (registry) and new host addresses, and constructs a HostUpdateRequest
// with addresses to add and/or remove. It fetches the current host info, determines which addresses
// need to be added or removed, and sets the corresponding fields in the request.
func toHostUpdateRequest(ctx context.Context, service *WorkerService, data types.HostUpdateData) (*ryinterface.HostUpdateRequest, error) {
	// Initialize the request with hostname
	hostUpdateRequest := &ryinterface.HostUpdateRequest{
		Name: data.HostName,
	}

	// Fetch current host information from the service
	hostInfo, err := service.getHostInfo(ctx, data.HostName, data.Accreditation.AccreditationName)
	if err != nil {
		return nil, err
	}

	// Get current addresses from the host info
	currentAddresses := hostInfo.Addresses

	// Track addresses to add and remove
	var addressesToAdd, addressesToRemove []string

	// Find addresses to add: new addresses that don't exist in current addresses
	for _, addr := range data.HostNewAddrs {
		if !slices.Contains(currentAddresses, addr) {
			addressesToAdd = append(addressesToAdd, addr)
		}
	}

	// Find addresses to remove: current addresses that are not in the new addresses
	for _, addr := range currentAddresses {
		if !slices.Contains(data.HostNewAddrs, addr) {
			addressesToRemove = append(addressesToRemove, addr)
		}
	}

	// Only create the remove element if we have addresses to remove
	if len(addressesToRemove) > 0 {
		hostUpdateRequest.Rem = &ryinterface.HostUpdateElement{
			Addresses: addressesToRemove,
		}
	}

	// Only create the add element if we have addresses to add
	if len(addressesToAdd) > 0 {
		hostUpdateRequest.Add = &ryinterface.HostUpdateElement{
			Addresses: addressesToAdd,
		}
	}

	return hostUpdateRequest, nil
}
