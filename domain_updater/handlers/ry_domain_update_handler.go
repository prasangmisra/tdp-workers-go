package handlers

import (
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

// RyDomainUpdateHandler receives the responses from the registry interface
// and updates the database
func (service *WorkerService) RyDomainUpdateHandler(server messagebus.Server, message proto.Message, job *model.Job, tx database.Database, logger logger.ILogger) (err error) {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "RyDomainUpdateHandler")
	defer service.tracer.FinishSpan(span)

	response := message.(*ryinterface.DomainUpdateResponse)

	logger.Debug(types.LogMessages.ReceivedResponseFromRY, log.Fields{
		types.LogFieldKeys.Response: response.String(),
	})

	data := new(types.DomainUpdateData)

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
		logger.Info("Domain successfully updated on the registry backend", log.Fields{
			types.LogFieldKeys.Domain: data.Name,
		})

		if job.Info.ReferenceID != nil {
			pdu := model.ProvisionDomainUpdate{
				ID:       *job.Info.ReferenceID,
				RyCltrid: &registryResponse.EppCltrid,
			}

			err = tx.UpdateProvisionDomainUpdate(ctx, &pdu)
			if err != nil {
				logger.Error("Error updating provision_domain_update with results", log.Fields{
					types.LogFieldKeys.Error: err,
				})

				resMsg := err.Error()
				job.ResultMessage = &resMsg
				err = tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
				if err != nil {
					logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
						types.LogFieldKeys.Error: err,
					})
				}
				return
			}
		}

		if registryResponse.EppCode == types.EppCode.Pending {
			err = tx.SetJobStatus(ctx, job, types.JobStatus.CompletedConditionally, &jrd)
			if err != nil {
				logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
					types.LogFieldKeys.Error: err,
				})
			}
			return
		}

		err = tx.SetJobStatus(ctx, job, types.JobStatus.Completed, &jrd)
		if err != nil {
			logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
		}
	} else {
		logger.Error("Failed to update domain in registry", log.Fields{
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
