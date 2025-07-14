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

func (service *WorkerService) CertificateRenewResponseHandler(server messagebus.Server, message proto.Message) (err error) {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "CertificateRenewResponseHandler")
	defer service.tracer.FinishSpan(span)

	response := message.(*certmessages.CertificateRenewedNotification)
	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.LogID: uuid.NewString(),
	})

	logger.Debug(types.LogMessages.ReceivedRenewResponseFromCertBE, log.Fields{
		types.LogFieldKeys.RequestID: response.RequestId,
		types.LogFieldKeys.Status:    response.Status.String(),
		types.LogFieldKeys.Message:   response.Message,
		types.LogFieldKeys.Domain:    response.Domain,
	})

	return service.db.WithTransaction(func(tx database.Database) (err error) {

		hosting, err := tx.GetHosting(ctx, &model.Hosting{ID: response.RequestId})
		// If lookup by RequestId fails, try again with the Domain name
		if err != nil {
			logger.Info("Could not find hosting by RequestID, attempting fallback by Domain", log.Fields{
				types.LogFieldKeys.HostingID: response.RequestId,
				types.LogFieldKeys.Domain:    response.Domain,
			})

			// This is the new fallback logic
			hosting, err = tx.GetHosting(ctx, &model.Hosting{
				DomainName: response.Domain,
				IsActive:   true,
				IsDeleted:  false,
			})
			if err != nil {
				logger.Error("Fallback by domain also failed", log.Fields{
					types.LogFieldKeys.Domain: response.Domain,
					types.LogFieldKeys.Error:  err,
				})
				return
			}
		}

		if response.Status == certmessages.CertStatus_CERT_STATUS_ERROR {
			// For now, we have only `Failed` status
			statusMsg := "Failed Certificate Renewal" // is this similar to response.Message?

			logger.Warn("Certificate renewal failed", log.Fields{
				types.LogFieldKeys.HostingID: hosting.ID,
				types.LogFieldKeys.Error:     response.Message,
			})

			hosting.HostingStatusID = types.ToPointer(tx.GetHostingStatusId(statusMsg))
			err = tx.UpdateHosting(ctx, hosting)
			if err != nil {
				log.Error("error updating hosting with status", log.Fields{
					types.LogFieldKeys.HostingID: hosting.ID,
					types.LogFieldKeys.Status:    statusMsg,
					types.LogFieldKeys.Error:     err,
				})
			}
			return
		}

		// create hosting update order
		order := &model.Order{
			TenantCustomerID: hosting.TenantCustomerID,
			TypeID:           tx.GetOrderTypeId("update", "hosting"),
			OrderItemUpdateHosting: model.OrderItemUpdateHosting{
				HostingID: hosting.ID,
				Certificate: &model.OrderItemUpdateHostingCertificate{
					Body:       response.Certificate.Cert,
					Chain:      &response.Certificate.Chain,
					PrivateKey: response.Certificate.PrivateKey,
					NotBefore:  *types.TimestampToTime(response.Certificate.NotBefore),
					NotAfter:   *types.TimestampToTime(response.Certificate.NotAfter),
				},
			},
		}

		logger.Info("Creating hosting update order", log.Fields{
			types.LogFieldKeys.HostingID: response.RequestId,
			"certificate_not_before":     response.Certificate.NotBefore.String(),
			"certificate_not_after":      response.Certificate.NotAfter.String(),
		})

		err = tx.CreateOrder(ctx, order)
		if err != nil {
			logger.Error("Error creating certificate update order", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}
		logger = logger.CreateChildLogger(log.Fields{
			types.LogFieldKeys.OrderID: order.ID,
		})
		// Update the order status to processing
		err = tx.OrderNextStatus(ctx, order.ID, true)
		if err != nil {
			logger.Error("Error marking order as processing", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}
		logger.Info("Certificate renewal order generated")
		return

	})
}
