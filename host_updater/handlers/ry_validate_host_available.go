package handlers

import (
	"context"
	"encoding/json"

	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/epp_utils"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// RyValidateHostAvailableHandler receives host check responses from the registry interface
// and updates the database
func RyValidateHostAvailableHandler(ctx context.Context, response *ryinterface.HostCheckResponse, job *model.Job, tx database.Database, logger logger.ILogger) (err error) {
	data := new(types.HostValidationData)

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

	oip := &model.OrderItemPlan{
		ID:                 data.OrderItemPlanId,
		ValidationStatusID: tx.GetOrderItemPlanValidationStatusId(types.OrderItemPlanValidationStatus.Completed),
	}

	if !registryResponse.GetIsSuccess() {
		logger.Error("Error checking host at registry", log.Fields{
			types.LogFieldKeys.Host:        data.HostName,
			types.LogFieldKeys.EppCode:     registryResponse.GetEppCode(),
			types.LogFieldKeys.EppMessage:  registryResponse.GetEppMessage(),
			types.LogFieldKeys.XmlResponse: registryResponse.GetXml(),
		})

		epp_utils.SetJobErrorFromRegistryResponse(registryResponse, job, &jrd)
		jobStatus = types.JobStatus.Failed
		oip.ValidationStatusID = tx.GetOrderItemPlanValidationStatusId(types.OrderItemPlanValidationStatus.Failed)
	} else if len(response.Hosts) != 1 {
		logger.Error("Invalid host check response received")

		resMsg := "host validation failed"
		job.ResultMessage = &resMsg
		jobStatus = types.JobStatus.Failed
		oip.ValidationStatusID = tx.GetOrderItemPlanValidationStatusId(types.OrderItemPlanValidationStatus.Failed)
	} else {
		host := response.Hosts[0]

		if !host.IsAvailable {
			logger.Info("Host already exists in registry; skipping provisioning", log.Fields{
				types.LogFieldKeys.Host: data.HostName,
			})
			// mark plan as completed to skip provisioning
			oip.StatusID = tx.GetOrderItemPlanStatusId(types.OrderItemPlanStatus.Completed)
		}
	}

	err = tx.UpdateOrderItemPlan(ctx, oip)
	if err != nil {
		logger.Error("Error updating order item plan", log.Fields{
			types.LogFieldKeys.Error: err,
		})

		resMsg := err.Error()
		job.ResultMessage = &resMsg
		return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
	}

	err = tx.SetJobStatus(ctx, job, jobStatus, &jrd)
	if err != nil {
		logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}

	return
}
