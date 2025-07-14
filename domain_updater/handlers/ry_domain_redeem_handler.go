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

// RyDomainRedeemHandler receives the responses from the registry interface
// and updates the database
func (service *WorkerService) RyDomainRedeemHandler(server messagebus.Server, message proto.Message, job *model.Job, tx database.Database, logger logger.ILogger) (err error) {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "RyDomainRedeemHandler")
	defer service.tracer.FinishSpan(span)

	response := message.(*ryinterface.DomainUpdateResponse)

	logger.Debug(types.LogMessages.ReceivedResponseFromRY, log.Fields{
		types.LogFieldKeys.Response: response.String(),
	})

	data := new(types.DomainRedeemData)

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
		logger.Info("Domain successfully redeemed in registry", log.Fields{
			types.LogFieldKeys.Domain: data.Name,
		})

		// get expiry after successful redemption
		jobType := *job.Info.JobTypeName
		if jobType == "provision_domain_redeem_report" || (jobType == "provision_domain_redeem" && !data.IsReportRequired) {
			service.handleDomainRedeemExpiryUpdate(ctx, logger, tx, job, data)
		}

		err = tx.SetJobStatus(ctx, job, types.JobStatus.Completed, &jrd)
		if err != nil {
			logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
		}
	} else {
		logger.Error("Failed to redeem domain in registry", log.Fields{
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

func (service *WorkerService) handleDomainRedeemExpiryUpdate(
	ctx context.Context,
	logger logger.ILogger,
	tx database.Database,
	job *model.Job,
	data *types.DomainRedeemData,
) {
	domainInfoResp, err := service.getDomainInfo(ctx, data.Name, data.Accreditation.AccreditationName)
	if err != nil || domainInfoResp == nil {
		logger.Error("Failed to get domain info after redemption", log.Fields{
			types.LogFieldKeys.Domain: data.Name,
			types.LogFieldKeys.Error:  err,
		})
		return
	}

	err = tx.UpdateProvisionDomainRedeem(ctx, &model.ProvisionDomainRedeem{
		ID:           *job.Info.ReferenceID,
		RyExpiryDate: domainInfoResp.ExpiryDate.AsTime(),
	})

	if err != nil {
		logger.Error("Failed to update domain expiry date after successful redemption", log.Fields{
			types.LogFieldKeys.Error:  err,
			types.LogFieldKeys.Domain: data.Name,
		})
	}
}
