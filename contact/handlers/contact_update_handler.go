package handlers

import (
	"encoding/json"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	commonmessages "github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// ContactUpdateHandler This is a callback handler for the ContactUpdate event
// and is in charge of sending the request to the registry interface
func (service *WorkerService) ContactUpdateHandler(server messagebus.Server, message proto.Message) error {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "ContactUpdateHandler")
	defer service.tracer.FinishSpan(span)

	// we need to type-cast the proto.Message to the wanted type
	request := message.(*job.Notification)
	jobId := request.GetJobId()

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: jobId,
	})

	logger.Info("Starting ContactUpdateHandler for the job")

	data := new(types.ContactUpdateData)

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

		logger.Info("Starting contact update job processing")

		if job.StatusID != tx.GetJobStatusId(types.JobStatus.Submitted) {
			logger.Warn(types.LogMessages.UnexpectedJobStatus, log.Fields{
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

		msg, err := toContactUpdateRequest(*data)
		if err != nil {
			logger.Error(types.LogMessages.ParseJobDataToRegistryRequestFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

		queue := types.GetTransformQueue(data.Accreditation.AccreditationName)
		headers := map[string]any{
			"reply_to":       "WorkerJobContactProvisionUpdate",
			"correlation_id": jobId,
		}

		err = server.MessageBus().Send(ctx, queue, msg, headers)
		if err != nil {
			logger.Error(types.LogMessages.MessageSendingToBusFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

		logger.Info(types.LogMessages.MessageSendingToBusSuccess, log.Fields{
			types.LogFieldKeys.Contact:              data.Handle,
			types.LogFieldKeys.MessageCorrelationID: jobId,
		})

		err = tx.SetJobStatus(ctx, job, types.JobStatus.Processing, nil)
		if err != nil {
			logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

		logger.Info(types.LogMessages.UpdateStatusInDBSuccess)

		return
	})
}

// toContactUpdateRequest converts ContactUpdateData to ryinterface's ContactUpdateRequest
func toContactUpdateRequest(data types.ContactUpdateData) (contactUpdateRequest *ryinterface.ContactUpdateRequest, err error) {

	contactUpdateRequest = &ryinterface.ContactUpdateRequest{
		Id:  data.Handle,
		Chg: &ryinterface.ContactChgBlock{},
	}

	// Email
	if data.Contact.Email != nil {
		contactUpdateRequest.Chg.Email = data.Contact.Email
	}

	// Voice
	if data.Contact.Phone != nil {
		contactUpdateRequest.Chg.Voice = data.Contact.Phone
	}

	// VoiceExt
	if data.Contact.PhoneExt != nil {
		contactUpdateRequest.Chg.VoiceExt = data.Contact.PhoneExt
	}

	// Fax
	if data.Contact.Fax != nil {
		contactUpdateRequest.Chg.Fax = data.Contact.Fax
	}

	// FaxExt
	if data.Contact.FaxExt != nil {
		contactUpdateRequest.Chg.FaxExt = data.Contact.FaxExt
	}

	// ContactPostals
	if data.Contact.ContactPostals != nil {
		contactPostals := data.Contact.ContactPostals
		var contactName *string
		if contactPostals[0].FirstName != nil || contactPostals[0].LastName != nil {
			contactName = types.ToPointer(
				types.SafeDeref(contactPostals[0].FirstName) + " " + types.SafeDeref(contactPostals[0].LastName),
			)
		}
		contactPostalInfo := commonmessages.ContactPostalInfo{
			Name: contactName,
			Org:  contactPostals[0].OrgName,
			Address: &commonmessages.ContactPostalAddress{
				Street1: contactPostals[0].Address1,
				Street2: contactPostals[0].Address2,
				Street3: contactPostals[0].Address3,
				City:    contactPostals[0].City,
				Sp:      contactPostals[0].State,
				Pc:      contactPostals[0].PostalCode,
				Cc:      data.Contact.Country,
			},
		}

		if *contactPostals[0].IsInternational {
			contactUpdateRequest.Chg.PostalInfoInt = &contactPostalInfo
		} else {
			contactUpdateRequest.Chg.PostalInfoLoc = &contactPostalInfo
		}
	}

	return
}
