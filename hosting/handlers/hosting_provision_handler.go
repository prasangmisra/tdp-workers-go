package handlers

import (
	"encoding/json"
	"errors"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// HostingProvisionHandler This is a callback handler for the Hosting provision event
// and is in charge of sending the request to the hosting api on AWS
func (service *WorkerService) HostingProvisionHandler(server messagebus.Server, message proto.Message) error {
	ctx := server.Context()

	request := message.(*job.Notification)
	jobId := request.GetJobId()

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: jobId,
	})

	logger.Info("Starting HostingProvisionHandler for the job")

	data := new(types.HostingData)

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

		logger.Info("Starting hosting provision job processing")

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

		response, err := service.createHosting(data, logger)
		if err != nil {
			logger.Error("Error creating hosting order for job", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			resMsg := err.Error()

			job.ResultMessage = &resMsg
			return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
		}

		upd := model.ProvisionHostingCreate{
			ExternalOrderID:  &response.Id,
			ExternalClientID: data.Client.ExternalClientId,
			ClientUsername:   &data.Client.Username,
			HostingStatusID:  types.ToPointer(tx.GetHostingStatusId(response.Status)),
			IsDeleted:        response.IsDeleted,
			StatusID:         tx.GetProvisionStatusId(types.ProvisionStatus.PendingAction),
		}

		if err = tx.UpdateProvisionHostingCreate(ctx, &upd, map[string]interface{}{"id": job.Info.ReferenceID}); err != nil && !errors.Is(err, database.ErrNotFound) {
			logger.Error("Error setting provision hosting details for hosting", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

		return tx.SetJobStatus(ctx, job, types.JobStatus.CompletedConditionally, nil)
	})
}

func (service *WorkerService) createHosting(data *types.HostingData, logger logger.ILogger) (response *OrderResponse, err error) {
	if data.Client.ExternalClientId == nil {
		var client *ClientResponse
		client, err = service.getOrCreateClient(data, logger)
		if err != nil {
			return
		}

		data.Client.ExternalClientId = &client.Id
		data.Client.Username = client.Username
	}

	return service.hostingApi.CreateHosting(createOrderRequest(data))
}

func (service *WorkerService) getOrCreateClient(data *types.HostingData, logger logger.ILogger) (client *ClientResponse, err error) {
	client, err = service.hostingApi.GetClientByEmail(data.Client.Email, data.CustomerName)
	if err != nil {
		logger.Error("Error getting client info for job", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	if client == nil {
		logger.Info("Client does not exist. Creating client for job")

		// just making sure it exists
		_, err = service.getOrCreateReseller(data, logger)
		if err != nil {
			return
		}

		request := createClientRequest(data)
		client, err = service.hostingApi.CreateClient(request)
		if err != nil {
			logger.Error("Error creating client for job", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}
	}

	return
}

func (service *WorkerService) getOrCreateReseller(data *types.HostingData, logger logger.ILogger) (reseller *ResellerResponse, err error) {
	reseller, err = service.hostingApi.GetResellerByName(data.CustomerName)
	if err != nil {
		logger.Error("Error getting reseller info for job", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	if reseller == nil {
		logger.Info("Reseller does not exist. Creating reseller for job")

		request := createResellerRequest(data)
		reseller, err = service.hostingApi.CreateReseller(request)
		if err != nil {
			logger.Error("Error creating reseller for job", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}
	}

	return
}
