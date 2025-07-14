package handlers

import (
	"context"
	"encoding/json"

	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/epp_utils"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// RyDomainTransferInRequestHandler receives the responses from the registry interface
// and updates the database
func (service *WorkerService) RyDomainTransferInRequestHandler(server messagebus.Server, message proto.Message, job *model.Job, tx database.Database, logger logger.ILogger) (err error) {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "RyDomainTransferInRequestHandler")
	defer service.tracer.FinishSpan(span)

	response := message.(*ryinterface.DomainTransferResponse)

	logger.Debug(types.LogMessages.ReceivedResponseFromRY, log.Fields{
		types.LogFieldKeys.Response: response.String(),
	})

	data := new(types.DomainTransferInRequestData)

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

	registryResponse := response.GetRegistryResponse()

	jrd := types.JobResultData{Message: message}

	if registryResponse.GetIsSuccess() {
		logger.Info("Transfer in request was successfully created for domain in registry", log.Fields{
			types.LogFieldKeys.Domain: data.Name,
		})

		if registryResponse.EppCode == types.EppCode.Pending {
			err = ProcessRyDomainTransferInResponse(ctx, response, job, tx, logger)
			if err != nil {
				logger.Error("Failed to process domain transfer in response", log.Fields{
					types.LogFieldKeys.Error: err,
				})

				resMsg := err.Error()
				job.ResultMessage = &resMsg
				return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
			}

			// Set the job status to completed conditionally
			err = tx.SetJobStatus(ctx, job, types.JobStatus.CompletedConditionally, &jrd)
			if err != nil {
				logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
					types.LogFieldKeys.Error: err,
				})
			}
		} else {
			logger.Warn("Unexpected EPP code in response for job", log.Fields{
				types.LogFieldKeys.EppCode: registryResponse.EppCode,
			})
		}
	} else {
		logger.Error("Failed to transfer domain in registry", log.Fields{
			types.LogFieldKeys.Domain:      data.Name,
			types.LogFieldKeys.EppCode:     registryResponse.GetEppCode(),
			types.LogFieldKeys.EppMessage:  registryResponse.GetEppMessage(),
			types.LogFieldKeys.XmlResponse: registryResponse.GetXml(),
		})

		epp_utils.SetJobErrorFromRegistryResponse(registryResponse, job, &jrd)
		err = tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
		if err != nil {
			logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
		}
	}

	return
}

// ProcessRyDomainTransferInResponse receives the domain transfer response from the registry and updates the database
func ProcessRyDomainTransferInResponse(ctx context.Context, response *ryinterface.DomainTransferResponse, job *model.Job, tx database.Database, logger logger.ILogger) (err error) {
	if job.Info.ReferenceID != nil {
		pdtr := model.ProvisionDomainTransferInRequest{
			ID:               *job.Info.ReferenceID,
			RequestedBy:      &response.RequestedBy,
			RequestedDate:    types.TimestampToTime(response.RequestedDate),
			ActionBy:         &response.ActionBy,
			ActionDate:       types.TimestampToTime(response.ActionDate),
			ExpiryDate:       types.TimestampToTime(response.ExpiryDate),
			TransferStatusID: tx.GetTransferStatusId(response.Status),
			StatusID:         tx.GetProvisionStatusId(types.ProvisionStatus.PendingAction),
		}

		err = tx.UpdateProvisionDomainTransferInRequest(ctx, &pdtr)
		if err != nil {
			logger.Error("Failed to update provision data in DB", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

		logger.Info("Provision data updated in DB", log.Fields{
			types.LogFieldKeys.Provision: pdtr,
		})
	}

	return
}
