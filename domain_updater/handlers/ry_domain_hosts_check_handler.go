package handlers

import (
	"context"
	"encoding/json"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/epp_utils"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// RyDomainHostsCheckHandler receives the domain info response from the registry interface
// and checks domain hosts to see if the domain can be deleted
func (service *WorkerService) RyDomainHostsCheckHandler(server messagebus.Server, message proto.Message, job *model.Job, tx database.Database, logger logger.ILogger) (err error) {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "RyDomainHostsCheckHandler")
	defer service.tracer.FinishSpan(span)

	response := message.(*ryinterface.DomainInfoResponse)

	logger.Debug(types.LogMessages.ReceivedResponseFromRY, log.Fields{
		types.LogFieldKeys.Response: response.String(),
	})

	data := new(types.DomainDeleteData)

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

	jobStatus := types.JobStatus.Completed

	if registryResponse.GetIsSuccess() {
		// Check if the domain is belong to the same registrar
		if response.Clid != data.Accreditation.RegistrarID {
			logger.Info("Domain does not belong to the registrar", log.Fields{
				types.LogFieldKeys.Domain: data.Name,
				"RegistrarID":             data.Accreditation.RegistrarID,
			})

			// Create a new data to transfer the domain to the correct registrar
			data := &types.DomainTransferAwayData{
				Name:             data.Name,
				Accreditation:    data.Accreditation,
				TenantCustomerId: data.TenantCustomerId,
				Metadata:         data.Metadata,
			}

			// Create a new order to transfer the domain to the correct registrar
			err = createTransferAwayOrder(ctx, tx, data, response)
			if err != nil {
				logger.Error("Failed to create transfer away order", log.Fields{
					types.LogFieldKeys.Error: err,
				})
			}

			// Fail the job to fail delete order
			job.ResultMessage = types.ToPointer("Domain does not belong to the registrar")
			return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
		}

		// Get the RGP extension from the response
		var rgpMsg *extension.RgpInfoResponse
		rgpMsg, err = handleRgpExtension(response.GetExtensions())
		if err != nil {
			logger.Error("Failed to handle RGP extension", log.Fields{
				types.LogFieldKeys.Error:  err,
				types.LogFieldKeys.Domain: data.Name,
			})

			// Fail the job to fail delete order
			job.ResultMessage = types.ToPointer("failed to handle RGP extension")
			return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
		}

		// Update domain delete data
		if rgpMsg.Rgpstatus == types.RgpStatus.RedemptionPeriod {
			logger.Info("Domain was deleted and is in redemption period", log.Fields{
				types.LogFieldKeys.Domain: data.Name,
			})

			// Set domain redemption grace period to true
			data.InRedemptionGracePeriod = true

			// Process the domain delete response
			err = ProcessRyDomainDeleteResponse(ctx, tx, registryResponse, data, job, logger)
			if err != nil {
				logger.Error("Failed to process domain delete response", log.Fields{
					types.LogFieldKeys.Error: err,
				})

				resMsg := err.Error()
				job.ResultMessage = &resMsg
				return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
			}
		} else if response.Hosts != nil {
			// Check if the domain has subordinated hosts
			logger.Info("Domain has subordinated hosts", log.Fields{
				types.LogFieldKeys.Domain: data.Name,
				"Hosts":                   response.Hosts,
			})

			// Set domain hosts
			data.Hosts = response.Hosts

			// Process the domain info response
			err = ProcessRyDomainInfoResponse(ctx, tx, response, data, job, logger)
			if err != nil {
				logger.Error("Failed to process domain info response", log.Fields{
					types.LogFieldKeys.Error: err,
				})

				resMsg := err.Error()
				job.ResultMessage = &resMsg
				return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
			}
		}
	} else if registryResponse.GetEppCode() == types.EppCode.ObjectDoesNotExist {
		// If the domain does not exist, complete the job.
		logger.Info("Domain does not exist in the registry", log.Fields{
			types.LogFieldKeys.Domain: data.Name,
		})

		// Set order metadata to indicate that the domain was not found
		data.Metadata["domain_not_found"] = true

		// Process the domain info response
		err = ProcessRyDomainInfoResponse(ctx, tx, response, data, job, logger)
		if err != nil {
			logger.Error("Failed to process domain info response", log.Fields{
				types.LogFieldKeys.Error: err,
			})

			resMsg := err.Error()
			job.ResultMessage = &resMsg
			return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
		}
	} else {
		logger.Error("Error getting domain info at registry", log.Fields{
			types.LogFieldKeys.Domain:      data.Name,
			types.LogFieldKeys.EppCode:     registryResponse.GetEppCode(),
			types.LogFieldKeys.EppMessage:  registryResponse.GetEppMessage(),
			types.LogFieldKeys.XmlResponse: registryResponse.GetXml(),
		})

		// Fail the job to fail delete order
		epp_utils.SetJobErrorFromRegistryResponse(registryResponse, job, &jrd)
		return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
	}

	// Set job status
	err = tx.SetJobStatus(ctx, job, jobStatus, &jrd)
	if err != nil {
		logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}

	return
}

// ProcessRyDomainInfoResponse processes the domain info response from the registry interface
func ProcessRyDomainInfoResponse(ctx context.Context, tx database.Database, response *ryinterface.DomainInfoResponse, data *types.DomainDeleteData, job *model.Job, logger logger.ILogger) (err error) {
	registryResponse := response.GetRegistryResponse()

	pdd := model.ProvisionDomainDelete{
		ID:       *job.Info.ReferenceID,
		RyCltrid: &registryResponse.EppCltrid,
	}

	if response.Hosts != nil {
		pdd.Hosts = response.Hosts
	} else if data.Metadata != nil {
		metadataBytes, err := json.Marshal(data.Metadata)
		if err != nil {
			logger.Error("Failed to marshal metadata", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return err
		}
		pdd.OrderMetadata = types.ToPointer(string(metadataBytes))
	}

	err = tx.UpdateProvisionDomainDelete(ctx, &pdd)
	if err != nil {
		logger.Error("Failed to update provision data in DB", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	logger.Info("Provision data updated in DB", log.Fields{
		types.LogFieldKeys.Provision: pdd,
	})

	return
}
