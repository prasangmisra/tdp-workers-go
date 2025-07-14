package handlers

import (
	"encoding/json"
	"time"

	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension"
	"github.com/tucowsinc/tdp-shared-go/logger"

	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/epp_utils"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// RyValidateDomainTransferableHandler receives the domain info response from the registry interface
// and updates the database
func (service *WorkerService) RyValidateDomainTransferableHandler(server messagebus.Server, message proto.Message, job *model.Job, tx database.Database, logger logger.ILogger) (err error) {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "RyValidateDomainTransferableHandler")
	defer service.tracer.FinishSpan(span)

	response := message.(*ryinterface.DomainInfoResponse)

	logger.Debug(types.LogMessages.ReceivedResponseFromRY, log.Fields{
		types.LogFieldKeys.Response: response.String(),
	})

	data := new(types.DomainTransferValidationData)

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

	jrd := types.JobResultData{Message: response}

	jobStatus := "completed"

	if !registryResponse.GetIsSuccess() || registryResponse.GetEppCode() != types.EppCode.Success {
		logger.Error("Error getting domain info at registry", log.Fields{
			types.LogFieldKeys.Domain:      data.Name,
			types.LogFieldKeys.EppCode:     registryResponse.GetEppCode(),
			types.LogFieldKeys.EppMessage:  registryResponse.GetEppMessage(),
			types.LogFieldKeys.XmlResponse: registryResponse.GetXml(),
		})

		epp_utils.SetJobErrorFromRegistryResponse(registryResponse, job, &jrd)
		jobStatus = types.JobStatus.Failed

		return tx.SetJobStatus(ctx, job, jobStatus, &jrd)
	}

	// check if the domain is already owned by the same accreditation
	if response.Clid == data.Accreditation.RegistrarID {
		logger.Info("Domain is already owned by the same accreditation", log.Fields{
			types.LogFieldKeys.Domain: data.Name,
			"RegistrarID":             data.Accreditation.RegistrarID,
		})

		job.ResultMessage = types.ToPointer("Domain is already owned by the same accreditation")
		return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
	}

	expiryDate := response.GetExpiryDate()
	newExpiryDate := expiryDate.AsTime().AddDate(int(data.TransferPeriod), 0, 0)
	maxExpiryDate := time.Now().AddDate(int(data.DomainMaxLifetime), 0, 0)

	if newExpiryDate.After(maxExpiryDate) {
		logger.Error("Domain transfer period exceeds maximum allowed lifetime", log.Fields{
			types.LogFieldKeys.Domain: data.Name,
		})

		job.ResultMessage = types.ToPointer("Domain transfer period exceeds maximum allowed lifetime")
		return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
	}

	for _, status := range response.GetStatuses() {
		// fail job if status is clientTransferProhibited or serverTransferProhibited
		if status == types.EPPStatusCode.ClientTransferProhibited || status == types.EPPStatusCode.ServerTransferProhibited {
			logger.Info("Domain is not transferable", log.Fields{
				types.LogFieldKeys.Domain: data.Name,
				types.LogFieldKeys.Status: status,
			})

			job.ResultMessage = types.ToPointer("Domain is not transferable")
			return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
		}
	}

	extensions := response.GetExtensions()

	// check rgp status
	if rgpExt, ok := extensions["rgp"]; ok {
		logger.Debug("RGP extension found in domain to be transferred", log.Fields{
			types.LogFieldKeys.Domain: data.Name,
		})
		rgpMsg := new(extension.RgpInfoResponse)

		if err = rgpExt.UnmarshalTo(rgpMsg); err != nil {
			logger.Error("Failed to unmarshal RGP extension", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			job.ResultMessage = types.ToPointer("Failed to handle extensions for domain to be transferred")

			return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
		}

		if rgpMsg.Rgpstatus == types.RgpStatus.TransferPeriod {
			job.ResultMessage = types.ToPointer("Domain is in transfer period")
			return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
		}
	}

	err = tx.SetJobStatus(ctx, job, jobStatus, &jrd)
	if err != nil {
		logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}

	return
}
