package handlers

import (
	"github.com/google/uuid"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	certmessages "github.com/tucowsinc/tdp-messages-go/message/certbot"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
	"google.golang.org/protobuf/proto"
)

func (service *WorkerService) CertificateCreateResponseHandler(server messagebus.Server, message proto.Message) (err error) {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "CertificateCreateResponseHandler")
	defer service.tracer.FinishSpan(span)

	response := message.(*certmessages.CertificateIssuedNotification)
	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.LogID: uuid.NewString(),
	})

	logger.Debug(types.LogMessages.ReceivedResponseFromCertBE, log.Fields{
		types.LogFieldKeys.RequestID: response.RequestId,
		types.LogFieldKeys.Status:    response.Status.String(),
		types.LogFieldKeys.Message:   response.Message,
		types.LogFieldKeys.Domain:    response.Domain,
	})

	return service.db.WithTransaction(func(tx database.Database) (err error) {

		// get the provision_hosting_certificate_create record
		// here we're using the hosting id as the request id, the
		// idea being when we sent the original create request
		// we passed the hosting id as the request id

		var provisionRecord *model.ProvisionHostingCertificateCreate

		if response.RequestId != "" {
			logger.Info("Fetching provision record by hosting ID", log.Fields{
				types.LogFieldKeys.HostingID: response.RequestId,
			})
			provisionRecord, err = tx.GetProvisionHostingCertififcate(ctx, &model.ProvisionHostingCertificateCreate{
				HostingID: response.RequestId,
				StatusID:  tx.GetProvisionStatusId(types.ProvisionStatus.PendingAction),
			})
			if err != nil {
				logger.Error("Error fetching provision record by hosting ID", log.Fields{
					types.LogFieldKeys.HostingID: response.RequestId,
					types.LogFieldKeys.Error:     err,
				})
				return
			}
		} else {
			logger.Info("Fetching provision record by domain name", log.Fields{
				types.LogFieldKeys.Domain: response.Domain,
			})

			provisionRecord, err = tx.GetProvisionHostingCertififcate(ctx, &model.ProvisionHostingCertificateCreate{
				DomainName: response.Domain,
				StatusID:   tx.GetProvisionStatusId(types.ProvisionStatus.PendingAction),
			})
			if err != nil {
				logger.Error("Error fetching provision record by domain name", log.Fields{
					types.LogFieldKeys.Domain: response.Domain,
					types.LogFieldKeys.Error:  err,
				})
				return
			}
		}

		if response.Status == certmessages.CertStatus_CERT_STATUS_ERROR {
			logger.Warn("Certificate creation failed on backend", log.Fields{
				types.LogFieldKeys.Status: response.Status.String(),
				types.LogFieldKeys.Error:  response.Message,
			})

			provisionRecord.ResultMessage = &response.Message
			provisionRecord.StatusID = tx.GetProvisionStatusId(types.ProvisionStatus.Failed)
		} else {
			logger.Info("Certificate successfully created on backend", log.Fields{
				types.LogFieldKeys.Status: response.Status.String(),
				"not_before":              response.Certificate.NotBefore.String(),
				"not_after":               response.Certificate.NotAfter.String(),
			})
			// update the record with the result data
			provisionRecord.Body = &response.Certificate.Cert
			provisionRecord.Chain = &response.Certificate.Chain
			provisionRecord.PrivateKey = &response.Certificate.PrivateKey
			provisionRecord.NotBefore = types.TimestampToTime(response.Certificate.NotBefore)
			provisionRecord.NotAfter = types.TimestampToTime(response.Certificate.NotAfter)
			provisionRecord.StatusID = tx.GetProvisionStatusId(types.ProvisionStatus.Completed)
		}

		err = tx.UpdateProvisionHostingCertificate(ctx, provisionRecord)
		if err != nil {
			logger.Error("Error updating provision record", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

		logger.Info("Provision record successfully updated")
		return
	})
}
