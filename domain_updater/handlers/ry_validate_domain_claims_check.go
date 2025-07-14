package handlers

import (
	"context"
	"encoding/json"

	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/epp_utils"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// RyValidateDomainClaimsHandler receives the domain claims check responses from the registry interface
// and updates the database
func RyValidateDomainClaimsHandler(ctx context.Context, response *ryinterface.DomainCheckResponse, job *model.Job, tx database.Database, logger logger.ILogger) (err error) {
	data := new(types.DomainClaimsValidationData)

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

	if !registryResponse.GetIsSuccess() || registryResponse.GetEppCode() != types.EppCode.Success {
		logger.Error("Error checking domain at registry", log.Fields{
			types.LogFieldKeys.Domain:      data.Name,
			types.LogFieldKeys.EppCode:     registryResponse.GetEppCode(),
			types.LogFieldKeys.EppMessage:  registryResponse.GetEppMessage(),
			types.LogFieldKeys.XmlResponse: registryResponse.GetXml(),
		})

		epp_utils.SetJobErrorFromRegistryResponse(registryResponse, job, &jrd)
		return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
	}

	ex := response.GetExtensions()

	var launchCheckResponse extension.LaunchCheckResponse
	err = ex["launch"].UnmarshalTo(&launchCheckResponse)
	if err != nil {
		logger.Error("Cannot decode launch extension data from domain claims check", log.Fields{
			types.LogFieldKeys.Error: err,
		})

		resMsg := "domain validation failed"
		job.ResultMessage = &resMsg
		return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
	}

	if len(launchCheckResponse.Data) != 1 {
		logger.Error("Invalid domain claim check response received", log.Fields{})

		resMsg := "domain validation failed"
		job.ResultMessage = &resMsg
		return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
	}

	// if exists, trademark exists which requires claims
	if launchCheckResponse.Data[0].Exists {
		// claims data provided  in order complete job successfully else fail the job
		if data.LaunchData == nil {
			logger.Error("Claims data is required but missing", log.Fields{})

			resMsg := "claims data is missing"
			job.ResultMessage = &resMsg
			return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
		}
	} else {
		// remove claims data from order + complete job successfully
		orderItem, err := tx.GetOrderItemCreateDomain(ctx, data.OrderItemId)
		if err != nil {
			logger.Error("Failed to get domain order", log.Fields{
				types.LogFieldKeys.Error: err,
			})

			resMsg := "domain validation failed"
			job.ResultMessage = &resMsg
			return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
		}

		orderItem.LaunchData = nil
		err = tx.UpdateOrderItemCreateDomain(ctx, orderItem)
		if err != nil {
			logger.Error("Failed to update domain order", log.Fields{
				types.LogFieldKeys.Error: err,
			})

			resMsg := "domain validation failed"
			job.ResultMessage = &resMsg
			return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
		}
	}

	err = tx.SetJobStatus(ctx, job, types.JobStatus.Completed, &jrd)
	if err != nil {
		logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}

	return
}
