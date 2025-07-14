package handlers

import (
	"encoding/json"

	"golang.org/x/exp/slices"
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

const ExpiryDateFormat string = "2006-01-02"

// DomainExpiryDateCheckHandler receives the domain info response from the registry interface
// and updates the database with right expiry date after make some calculations
func (service *WorkerService) RyDomainExpiryDateCheckHandler(server messagebus.Server, message proto.Message, job *model.Job, tx database.Database, logger logger.ILogger) (err error) {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "RyDomainExpiryDateCheckHandler")
	defer service.tracer.FinishSpan(span)

	response := message.(*ryinterface.DomainInfoResponse)

	logger.Debug(types.LogMessages.ReceivedResponseFromRY, log.Fields{
		types.LogFieldKeys.Response: response.String(),
	})

	data := new(types.DomainRenewData)

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
		logger.Error("Error getting domain info at registry", log.Fields{
			types.LogFieldKeys.Domain:      data.Name,
			types.LogFieldKeys.EppCode:     registryResponse.GetEppCode(),
			types.LogFieldKeys.EppMessage:  registryResponse.GetEppMessage(),
			types.LogFieldKeys.XmlResponse: registryResponse.GetXml(),
		})

		epp_utils.SetJobErrorFromRegistryResponse(registryResponse, job, &jrd)
		return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
	}

	// check if the domain is belong to the same registrar
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

		// Fail the job to fail renew order
		job.ResultMessage = types.ToPointer("Domain does not belong to the registrar")
		return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
	}

	// check if the domain statuses include ClientRenewProhibited or ServerRenewProhibited
	if slices.Contains(response.GetStatuses(), types.EPPStatusCode.ClientRenewProhibited) || slices.Contains(response.GetStatuses(), types.EPPStatusCode.ServerRenewProhibited) {
		logger.Info("Status prohibits operation", log.Fields{
			types.LogFieldKeys.Domain: data.Name,
			"Statuses":                response.GetStatuses(),
		})

		job.ResultMessage = types.ToPointer("Status prohibits operation")
		return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
	}

	ryExpiryDate := response.GetExpiryDate().AsTime()
	dbExpiryDate := data.ExpiryDate

	if ryExpiryDate.Day() != dbExpiryDate.Day() || ryExpiryDate.Month() != dbExpiryDate.Month() {
		logger.Error("Domain expiry dates have day/month mismatch", log.Fields{
			types.LogFieldKeys.Domain: data.Name,
			types.LogFieldKeys.Error:  "Domain expiry dates have day/month mismatch between registry and database",
		})

		// Fail the job to fail renew order
		job.ResultMessage = types.ToPointer("Domain expiry dates have day/month mismatch between registry and database")
		return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
	} else {
		logger.Info("Mismatch exists in domain expiry dates between registry and database", log.Fields{
			types.LogFieldKeys.Domain: data.Name,
			"current_expiry_date":     dbExpiryDate.Format(ExpiryDateFormat),
			"ry_expiry_date":          ryExpiryDate.Format(ExpiryDateFormat),
		})

		renewPeriod := int(*data.Period)                       // From the original order
		periodGap := ryExpiryDate.Year() - dbExpiryDate.Year() // Calculate the gap between registry and database expiry years

		provisionData := &model.ProvisionDomainRenew{
			ID:                *job.Info.ReferenceID,
			RyCltrid:          &registryResponse.EppCltrid,
			CurrentExpiryDate: ryExpiryDate,
			Period:            types.ToPointer(int32(renewPeriod - periodGap)),
		}

		// If the period gap is greater than the renew period, just do what customer wanted
		if periodGap > renewPeriod {
			provisionData.Period = types.ToPointer(int32(renewPeriod))
		}

		// If the period gap is equal to the renew period, update the expiry date
		if periodGap == renewPeriod {
			provisionData.RyExpiryDate = &ryExpiryDate
		}

		err = tx.UpdateProvisionDomainRenew(ctx, provisionData)
		if err != nil {
			logger.Error("Failed to record provision domain renew", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			job.ResultMessage = types.ToPointer("Failed to record provision domain renew")
			return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
		}

		return tx.SetJobStatus(ctx, job, types.JobStatus.Completed, &jrd)
	}
}
