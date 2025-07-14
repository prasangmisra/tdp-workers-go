package handlers

import (
	"encoding/json"
	"fmt"

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

// ContactProvisionHandler This is a callback handler for the ContactProvision event
// and is in charge of sending the request to the registry interface
func (service *WorkerService) ContactProvisionHandler(server messagebus.Server, message proto.Message) error {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "ContactProvisionHandler")
	defer service.tracer.FinishSpan(span)

	// we need to type-cast the proto.Message to the wanted type
	request := message.(*job.Notification)
	jobId := request.GetJobId()

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: jobId,
	})

	logger.Info("Starting ContactProvisionHandler for the job")

	data := new(types.ContactData)

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

		logger.Info("Starting contact provision job processing")

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

		var contactName *string
		if data.Contact.ContactPostals[0].FirstName != nil || data.Contact.ContactPostals[0].LastName != nil {
			contactName = types.ToPointer(
				types.SafeDeref(data.Contact.ContactPostals[0].FirstName) + " " + types.SafeDeref(data.Contact.ContactPostals[0].LastName),
			)
		}

		//contact id is the prefix tdp- and the last 12 of the UUID
		contactId := fmt.Sprintf("tdp-%s", jobId[len(jobId)-12:])
		contactPostalInfo := commonmessages.ContactPostalInfo{
			Org:  data.Contact.ContactPostals[0].OrgName,
			Name: contactName,
			Address: &commonmessages.ContactPostalAddress{
				Street1: data.Contact.ContactPostals[0].Address1,
				Street2: data.Contact.ContactPostals[0].Address2,
				Street3: data.Contact.ContactPostals[0].Address3,
				City:    data.Contact.ContactPostals[0].City,
				Sp:      data.Contact.ContactPostals[0].State,
				Pc:      data.Contact.ContactPostals[0].PostalCode,
				Cc:      data.Contact.Country,
			},
		}

		msg := ryinterface.ContactCreateRequest{
			Id:       contactId,
			Email:    data.Contact.Email,
			Voice:    data.Contact.Phone,
			VoiceExt: data.Contact.PhoneExt,
			Pw:       &data.Pw,
			Fax:      data.Contact.Fax,
			FaxExt:   data.Contact.FaxExt,
		}

		if *data.Contact.ContactPostals[0].IsInternational {
			msg.PostalInfoInt = &contactPostalInfo
		} else {
			msg.PostalInfoLoc = &contactPostalInfo
		}

		queue := types.GetTransformQueue(data.Accreditation.AccreditationName)
		headers := map[string]any{
			"reply_to":       "WorkerJobContactProvisionUpdate",
			"correlation_id": jobId,
		}

		err = server.MessageBus().Send(ctx, queue, &msg, headers)
		if err != nil {
			logger.Error(types.LogMessages.MessageSendingToBusFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

		logger.Info(types.LogMessages.MessageSendingToBusSuccess, log.Fields{
			types.LogFieldKeys.Contact:              data.Contact,
			types.LogFieldKeys.MessageCorrelationID: jobId,
		})

		err = tx.SetProvisionContactHandle(ctx, *job.Info.ReferenceID, contactId)
		if err != nil {
			logger.Error("Error setting provision contact handle", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

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
