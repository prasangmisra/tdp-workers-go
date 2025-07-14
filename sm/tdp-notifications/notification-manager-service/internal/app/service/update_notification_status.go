package service

import (
	"context"
	"os"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/tucowsinc/tdp-messages-go/message/datamanager"
	nmerrors "github.com/tucowsinc/tdp-notifications/notification-manager-service/internal/app/errors"
	"github.com/tucowsinc/tdp-notifications/notification-manager-service/internal/app/model"
)

func (s *Service) UpdateNotificationStatus(ctx context.Context, msg *datamanager.Notification) error {
	// We have received a message that contains the "final" status of a notification (i.e. PUBLISHED, FAILED, etc)
	// Update the database with this status!

	// Only handle cases where the status is "published" or "failed"
	if msg.Status != datamanager.DeliveryStatus_FAILED && msg.Status != datamanager.DeliveryStatus_PUBLISHED {
		return nmerrors.ErrInvalidFinalStatus
	}

	// Convert the proto message back to a VNotification gorm object
	vnotification, err := model.VNotificationFromProto(msg)
	if err != nil {
		return nmerrors.ErrInvalidNotification
	}

	// Update the gorm object!
	rows, err := s.vnotificationRepo.Update(ctx, s.subDB, vnotification)
	if err != nil {
		switch err.(type) {
		case *pgconn.ConnectError: // Note that the usual "errors.Is(err, pgconn.ConnectError)" syntax DOES NOT WORK here
			// Database connectivity error!
			// In this case, the service has lost connectivity to the database.  We consider this service compromised!
			// We will now shut down the service. Presumably, there will be a worker that will start a new instance of the service
			// and that new instance should have a working database connection.
			s.subDB.GetDB().Logger.Error(ctx, "Database connectivity error; service is shutting down", err)
			// Note that the following exit call will return the message back to the queue, and the message will be reprocessed by another instance of the service
			os.Exit(1)
		default:
			// For all other reasons, kick an error back to the handler
			return nmerrors.ErrDatabaseUpdateFailed
		}
	}
	if rows == 0 {
		// No rows updated means the notification was not found
		return nmerrors.ErrNotFound
	}
	return nil
}
