package handlers

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	tcwire "github.com/tucowsinc/tdp-messages-go/message"
	"github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/epp_utils"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

const MaxRetries int32 = 3

func (service *WorkerService) RyTimeoutHandler(server messagebus.Server, message proto.Message) (err error) {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "RyTimeoutHandler")
	defer service.tracer.FinishSpan(span)

	correlationId := server.Envelope().CorrelationId

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: correlationId,
	})

	response := message.(*tcwire.ErrorResponse)

	logger.Info("Received timeout error response from RY interface", log.Fields{
		types.LogFieldKeys.Response: response.GetMessage(),
	})

	job, err := service.db.GetJobById(ctx, correlationId, true)
	if err != nil {
		logger.Error(types.LogMessages.FetchJobByIDFromDBFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	jobType := *job.Info.JobTypeName

	logger = logger.CreateChildLogger(log.Fields{
		types.LogFieldKeys.LogID:   uuid.NewString(),
		types.LogFieldKeys.JobType: jobType,
	})

	logger.Info("Starting reconciliation process for job")

	err = JobReconcilerRouter(service, ctx, response, job, logger)
	if err != nil {
		logger.Error("Reconciliation process failed for job", log.Fields{
			types.LogFieldKeys.Error: err,
		})

		job.ResultMessage = getJobResultMsg(jobType)
		err = service.db.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
		if err != nil {
			logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}
	}

	logger.Info("Reconciliation process was successful for job")

	return
}

// JobReconcilerRouter routes the job to the appropriate reconciliation handler
func JobReconcilerRouter(service *WorkerService, ctx context.Context, message *tcwire.ErrorResponse, job *model.Job, logger logger.ILogger) (err error) {
	jobType := *job.Info.JobTypeName

	switch jobType {
	case "provision_domain_renew":
		err = renewDomain(service, ctx, message, job, logger)
	case "provision_domain_create":
		err = createDomain(service, ctx, message, job, logger)
	case "provision_domain_transfer_in_request":
		err = transferInDomain(service, ctx, message, job, logger)
	case "provision_domain_delete":
		err = deleteDomain(service, ctx, message, job, logger)
	case "provision_domain_redeem", "provision_domain_redeem_report":
		err = redeemDomain(service, ctx, message, job, logger)
	case "provision_domain_transfer_in":
		err = transferInInfoDomain(service, ctx, message, job, logger)
	default:
		err = fmt.Errorf("unsupported job type: %s", jobType)
	}

	return
}

// renewDomain renews the domain if needed
func renewDomain(service *WorkerService, ctx context.Context, message *tcwire.ErrorResponse, job *model.Job, logger logger.ILogger) (err error) {
	// Get the job result data
	jrd := types.JobResultData{Message: message}

	// Get the database instance
	db := service.db

	// Get the reference ID
	refId, err := getJobReferenceID(ctx, db, job)
	if err != nil {
		logger.Error("Failed to get reference ID from job data", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	// Get the provision data from the DB
	renewRequest, err := db.GetProvisionDomainRenew(ctx, *refId)
	if err != nil {
		logger.Error("Failed to get provision data from DB", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}
	domainName := renewRequest.DomainName

	// Retry the job chain
	if *renewRequest.AllowedAttempts <= MaxRetries {
		logger.Info("Retrying domain renew provision in registry", log.Fields{
			types.LogFieldKeys.Domain: domainName,
			"allowed_attempts":        *renewRequest.AllowedAttempts,
		})

		// Incrementing allowed attempts for retry
		*renewRequest.AllowedAttempts++

		// Update the provision data in the DB
		err = db.UpdateProvisionDomainRenew(ctx, renewRequest)
		if err != nil {
			logger.Error("Failed to update provision data in DB", log.Fields{
				types.LogFieldKeys.Error: err,
			})
		}
	} else {
		logger.Info("Reconciliation process exceeded max retries", log.Fields{
			types.LogFieldKeys.Domain: domainName,
			"allowed_attempts":        *renewRequest.AllowedAttempts,
			"max_retries":             MaxRetries,
		})

		// Set the job result message
		epp_utils.SetJobErrorFromRegistryErrorResponse(message, job, &jrd)
	}

	// Fail the job
	err = db.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
	if err != nil {
		logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}

	return
}

// createDomain creates the domain if needed
func createDomain(service *WorkerService, ctx context.Context, message *tcwire.ErrorResponse, job *model.Job, logger logger.ILogger) (err error) {
	// Get the job result data
	jrd := types.JobResultData{Message: message}

	// Get the database instance
	db := service.db

	// Get the reference ID
	refId, err := getJobReferenceID(ctx, db, job)
	if err != nil {
		logger.Error("Failed to get reference ID from job data", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	// Get the provision data from the DB
	createRequest, err := db.GetProvisionDomain(ctx, *refId)
	if err != nil {
		logger.Error("Failed to get provision data from DB", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}
	domainName := createRequest.DomainName

	// Get the accreditation from the job data
	acc, err := getAccreditationFromJob(job)
	if err != nil {
		logger.Error("Failed to get accreditation from job data", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}
	accName := acc.AccreditationName

	// Complete the job if the domain is already created in the registry
	domainInfoResp, err := service.getDomainInfo(ctx, domainName, accName)
	if err == nil && domainInfoResp.GetRegistryResponse().GetEppCode() == types.EppCode.Success && domainInfoResp.Clid == acc.RegistrarID {
		logger.Info("Domain already exists in registry", log.Fields{
			types.LogFieldKeys.Domain:        domainName,
			types.LogFieldKeys.Accreditation: accName,
		})

		jrd := types.JobResultData{Message: domainInfoResp}

		// Get domain provision response
		response := &ryinterface.DomainCreateResponse{
			Name:        domainName,
			CreatedDate: domainInfoResp.CreatedDate,
			ExpiryDate:  domainInfoResp.ExpiryDate,
			RegistryResponse: &common.RegistryResponse{
				EppCltrid: domainInfoResp.GetRegistryResponse().EppCltrid,
			},
		}

		// Process the domain provision response
		err = ProcessRyDomainProvisionResponse(ctx, response, job, db, logger)
		if err != nil {
			logger.Error("Failed to process domain provision response", log.Fields{
				types.LogFieldKeys.Error: err,
			})

			resMsg := err.Error()
			job.ResultMessage = &resMsg
			return db.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
		}

		// Set the job status to completed
		err = db.SetJobStatus(ctx, job, types.JobStatus.Completed, &jrd)
		if err != nil {
			logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
		}

		return
	}

	// Retry the job chain
	if *createRequest.AllowedAttempts <= MaxRetries {
		logger.Info("Retrying domain provision in registry", log.Fields{
			types.LogFieldKeys.Domain: domainName,
			"allowed_attempts":        *createRequest.AllowedAttempts,
		})

		// Incrementing allowed attempts for retry
		*createRequest.AllowedAttempts++

		// Update the provision data in the DB
		err = db.UpdateProvisionDomain(ctx, createRequest)
		if err != nil {
			logger.Error("Failed to update provision data in DB", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}
	} else {
		logger.Info("Reconciliation process exceeded max retries", log.Fields{
			types.LogFieldKeys.Domain: domainName,
			"allowed_attempts":        *createRequest.AllowedAttempts,
			"max_retries":             MaxRetries,
		})

		// Set the job result message
		epp_utils.SetJobErrorFromRegistryErrorResponse(message, job, &jrd)
	}

	// Fail the job
	err = db.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
	if err != nil {
		logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}

	return
}

// transferInDomain transfers in the domain if needed
func transferInDomain(service *WorkerService, ctx context.Context, message *tcwire.ErrorResponse, job *model.Job, logger logger.ILogger) (err error) {
	// Get the job result data
	jrd := types.JobResultData{Message: message}

	// Get the database instance
	db := service.db

	// Get the reference ID
	refId, err := getJobReferenceID(ctx, db, job)
	if err != nil {
		logger.Error("Failed to get reference ID from job data", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	// Get the provision data from the DB
	transferInRequest, err := db.GetProvisionDomainTransferInRequest(ctx, &model.ProvisionDomainTransferInRequest{ID: *refId})
	if err != nil {
		logger.Error("Failed to get provision data from DB", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}
	domainName := transferInRequest.DomainName

	// Get the accreditation from the job data
	acc, err := getAccreditationFromJob(job)
	if err != nil {
		logger.Error("Failed to get accreditation from job data", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}
	accName := acc.AccreditationName

	// Complete the job if the registry already received the transfer in request
	domainTransferResp, err := service.getTransferInfo(ctx, domainName, transferInRequest.Pw, accName)
	if err == nil && domainTransferResp.GetRegistryResponse().GetEppCode() == types.EppCode.Success {
		logger.Info("Transfer in request was successfully created for domain in registry", log.Fields{
			types.LogFieldKeys.Domain:        domainName,
			types.LogFieldKeys.Accreditation: accName,
			types.LogFieldKeys.Status:        domainTransferResp.GetStatus(),
		})

		// Job result data
		jrd := types.JobResultData{Message: domainTransferResp}

		// Process the domain transfer in response
		err = ProcessRyDomainTransferInResponse(ctx, domainTransferResp, job, db, logger)
		if err != nil {
			logger.Error("Failed to process domain transfer in response", log.Fields{
				types.LogFieldKeys.Error: err,
			})

			resMsg := err.Error()
			job.ResultMessage = &resMsg
			return db.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
		}

		// Set the job status to completed conditionally
		err = db.SetJobStatus(ctx, job, types.JobStatus.CompletedConditionally, &jrd)
		if err != nil {
			logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
		}

		return
	}

	// Retry the job chain
	if *transferInRequest.AllowedAttempts <= MaxRetries {
		logger.Info("Retrying domain transfer in provision in registry", log.Fields{
			types.LogFieldKeys.Domain: domainName,
			"allowed_attempts":        *transferInRequest.AllowedAttempts,
		})

		// Incrementing allowed attempts for retry
		*transferInRequest.AllowedAttempts++

		// Update the provision data in the DB
		err = db.UpdateProvisionDomainTransferInRequest(ctx, transferInRequest)
		if err != nil {
			logger.Error("Failed to update provision data in DB", log.Fields{
				types.LogFieldKeys.Error: err,
			})
		}
	} else {
		logger.Info("Reconciliation process exceeded max retries", log.Fields{
			types.LogFieldKeys.Domain: domainName,
			"allowed_attempts":        *transferInRequest.AllowedAttempts,
			"max_retries":             MaxRetries,
		})

		// Set the job result message
		epp_utils.SetJobErrorFromRegistryErrorResponse(message, job, &jrd)
	}

	// Fail the job
	err = db.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
	if err != nil {
		logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}

	return
}

// deleteDomain deletes the domain if needed
func deleteDomain(service *WorkerService, ctx context.Context, message *tcwire.ErrorResponse, job *model.Job, logger logger.ILogger) (err error) {
	// Get the job result data
	jrd := types.JobResultData{Message: message}

	// Get the database instance
	db := service.db

	// Get the reference ID
	refId, err := getJobReferenceID(ctx, db, job)
	if err != nil {
		logger.Error("Failed to get reference ID from job data", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	// Get the delete request details from the DB
	deleteRequest, err := db.GetProvisionDomainDelete(ctx, *refId)
	if err != nil {
		logger.Error("Failed to get delete request from DB", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}
	domainName := deleteRequest.DomainName

	// Retry the job chain
	if *deleteRequest.AllowedAttempts <= MaxRetries {
		logger.Info("Retrying domain delete provision in registry", log.Fields{
			types.LogFieldKeys.Domain: domainName,
			"allowed_attempts":        *deleteRequest.AllowedAttempts,
		})

		// Incrementing allowed attempts for retry
		*deleteRequest.AllowedAttempts++

		// Update the provision data in the DB
		err = db.UpdateProvisionDomainDelete(ctx, deleteRequest)
		if err != nil {
			logger.Error("Failed to update provision data in DB", log.Fields{
				types.LogFieldKeys.Error: err,
			})
		}
	} else {
		logger.Info("Reconciliation process exceeded max retries", log.Fields{
			types.LogFieldKeys.Domain: domainName,
			"allowed_attempts":        *deleteRequest.AllowedAttempts,
			"max_retries":             MaxRetries,
		})

		// Set the job result message
		epp_utils.SetJobErrorFromRegistryErrorResponse(message, job, &jrd)
	}

	// Fail the job
	err = db.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
	if err != nil {
		logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}

	return
}

// redeemDomain redeems the domain if needed
func redeemDomain(service *WorkerService, ctx context.Context, message *tcwire.ErrorResponse, job *model.Job, logger logger.ILogger) (err error) {
	// Get the job result data
	jrd := types.JobResultData{Message: message}

	// Get the database instance
	db := service.db

	// Get the reference ID
	refId, err := getJobReferenceID(ctx, db, job)
	if err != nil {
		logger.Error("Failed to get reference ID from job data", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	// Get the redeem request details from the DB
	redeemRequest, err := db.GetProvisionDomainRedeem(ctx, *refId)
	if err != nil {
		logger.Error("Failed to get redeem request from DB", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}
	domainName := redeemRequest.DomainName

	// Get the accreditation from the job data
	acc, err := getAccreditationFromJob(job)
	if err != nil {
		logger.Error("Failed to get accreditation from job data", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}
	accName := acc.AccreditationName

	// Complete the job if the registry already redeemed the domain
	domainInfoResp, err := service.getDomainInfo(ctx, domainName, accName)
	if err == nil && domainInfoResp.GetRegistryResponse().GetEppCode() == types.EppCode.Success && domainInfoResp.Clid == acc.RegistrarID && !rgpStatusExists(domainInfoResp.GetExtensions()) {
		logger.Info("Domain already redeemed by the registry", log.Fields{
			types.LogFieldKeys.Domain:        domainName,
			types.LogFieldKeys.Accreditation: accName,
		})

		err = db.SetJobStatus(ctx, job, types.JobStatus.Completed, nil)
		if err != nil {
			logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
		}

		return
	}

	// Retry the job chain
	if *redeemRequest.AllowedAttempts <= MaxRetries {
		logger.Info("Retrying domain redeem provision in registry", log.Fields{
			types.LogFieldKeys.Domain: domainName,
		})

		// Incrementing allowed attempts for retry
		*redeemRequest.AllowedAttempts++

		// Send the redeem report request only if the domain rgp status is pending restore
		if domainInfoResp != nil {
			rgpMsg, err := handleRgpExtension(domainInfoResp.GetExtensions())
			if err == nil && rgpMsg != nil && rgpMsg.Rgpstatus == types.RgpStatus.PendingRestore {
				logger.Info("Domain RGP status is pending restore in the registry and waiting for report request", log.Fields{
					types.LogFieldKeys.Domain:        domainName,
					types.LogFieldKeys.Accreditation: accName,
				})

				// Set in_pending_restore_status flag to true
				*redeemRequest.InRestorePendingStatus = true
			}
		}

		// Update the provision data in the DB
		err = db.UpdateProvisionDomainRedeem(ctx, redeemRequest)
		if err != nil {
			logger.Error("Failed to update provision data in DB", log.Fields{
				types.LogFieldKeys.Domain: domainName,
				types.LogFieldKeys.Error:  err,
			})
		}
	} else {
		logger.Info("Reconciliation process exceeded max retries", log.Fields{
			types.LogFieldKeys.Domain: domainName,
		})

		// Set the job result message
		epp_utils.SetJobErrorFromRegistryErrorResponse(message, job, &jrd)
	}

	// Fail the job
	err = db.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
	if err != nil {
		logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}

	return
}

// transferInInfoDomain handles the transfer in info domain
func transferInInfoDomain(service *WorkerService, ctx context.Context, message *tcwire.ErrorResponse, job *model.Job, logger logger.ILogger) (err error) {
	// Get the job result data
	jrd := types.JobResultData{Message: message}

	// Get the database instance
	db := service.db

	// Get the reference ID
	refId, err := getJobReferenceID(ctx, db, job)
	if err != nil {
		logger.Error("Failed to get reference ID from job data", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	// Get the transfer in request details from the DB
	transferInRequest, err := db.GetProvisionDomainTransferIn(ctx, *refId)
	if err != nil {
		logger.Error("Failed to get transfer in request from DB", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}
	domainName := transferInRequest.DomainName

	// Retry the job chain
	if *transferInRequest.AllowedAttempts <= MaxRetries {
		logger.Info("Retrying domain transfer in info provision in registry", log.Fields{
			types.LogFieldKeys.Domain: domainName,
		})

		// Incrementing allowed attempts for retry
		*transferInRequest.AllowedAttempts++

		// Update the provision data in the DB
		err = db.UpdateProvisionDomainTransferIn(ctx, transferInRequest)
		if err != nil {
			logger.Error("Failed to update provision data in DB", log.Fields{
				types.LogFieldKeys.Domain: domainName,
				types.LogFieldKeys.Error:  err,
			})
			return
		}
	} else {
		logger.Info("Reconciliation process exceeded max retries", log.Fields{
			types.LogFieldKeys.Domain: domainName,
		})

		// Set the job result message
		epp_utils.SetJobErrorFromRegistryErrorResponse(message, job, &jrd)
	}

	// Fail the job
	err = db.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
	if err != nil {
		logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}

	return
}

// getJobResultMsg returns the job result message based on the job type
func getJobResultMsg(jobType string) *string {
	var msg string

	switch jobType {
	case "provision_domain_renew":
		msg = "Timeout error occurred while renewing domain in registry"
	case "provision_domain_create":
		msg = "Timeout error occurred while creating domain in registry"
	case "provision_domain_transfer_in_request", "provision_domain_transfer_in":
		msg = "Timeout error occurred while transferring in domain"
	case "provision_domain_delete":
		msg = "Timeout error occurred while deleting domain in registry"
	case "provision_domain_redeem", "provision_domain_redeem_report":
		msg = "Timeout error occurred while redeeming domain in registry"
	default:
		msg = "Failed to process job"
	}

	return &msg
}

// getAccreditationFromJob returns the accreditation from the job data
func getAccreditationFromJob(job *model.Job) (*types.Accreditation, error) {
	var data types.DomainInfoData
	err := json.Unmarshal(job.Info.Data, &data)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal job data: %w", err)
	}

	return &data.Accreditation, nil
}

// getJobReferenceID returns the reference ID from the job data
func getJobReferenceID(ctx context.Context, db database.Database, job *model.Job) (refId *string, err error) {
	if job.Info.ReferenceID != nil {
		return job.Info.ReferenceID, nil
	}

	// Get the parent job
	parentJob, err := db.GetJobById(ctx, *job.Info.JobParentID, true)
	if err != nil {
		return nil, fmt.Errorf("failed to get parent job: %w", err)
	}

	refId = parentJob.Info.ReferenceID
	if refId == nil {
		return nil, fmt.Errorf("failed to get reference ID from parent job")
	}

	return refId, nil
}
