package handlers

import (
	"errors"
	"fmt"

	"github.com/tucowsinc/tdp-messages-go/message/worker"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// PollMessageHandler This is a callback handler for processing poll messages
func (service *WorkerService) PollMessageHandler(server messagebus.Server, message proto.Message) (err error) {
	ctx := server.Context()

	// We need to type-cast the proto.Message to the wanted type
	request := message.(*worker.PollMessage)

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.RequestID: request.Id,
		LogFieldKeys.PollMessageID:   request.Id,
		LogFieldKeys.PollMessageType: request.Type,
		LogFieldKeys.Accreditation:   request.Accreditation,
	})

	logger.Debug("Received poll message")

	msg := model.PollMessage{
		ID: request.Id,
	}

	isHandled := false
	for _, handler := range service.pollHandlers {
		if handler.Matches(request) {
			err = handler.Handle(ctx, service, request, logger)
			if errors.Is(err, ErrDeferMessage) {
				log.Info("Deferring poll message", log.Fields{
					types.LogFieldKeys.RequestID: request.Id,
					LogFieldKeys.Accreditation:   request.Accreditation,
					types.LogFieldKeys.Error:     err,
				})
				return nil
			}
			isHandled = true
		}
	}

	if !isHandled {
		err = fmt.Errorf("unknown poll message %q type: %v", request.Id, request.Type)
		logger.Error("Unknown poll message type", log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}

	if err != nil {
		// skip temporary failures
		if errors.Is(err, ErrTempRyFailure) {
			logger.Warn("Temporary failure detected, skipping for now", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return nil
		}

		logger.Error("Failed to process poll message", log.Fields{
			types.LogFieldKeys.Error: err,
		})

		dbErr := service.db.UpdatePollMessageStatus(ctx, msg.ID, types.PollMessageStatus.Failed)
		if dbErr != nil {
			logger.Error("Failed to update poll message status to failed", log.Fields{
				types.LogFieldKeys.Error: dbErr,
			})
			err = dbErr
		}
		return
	}

	// mark poll message as processed
	err = service.db.UpdatePollMessageStatus(ctx, msg.ID, types.PollMessageStatus.Processed)
	if err != nil {
		logger.Error("Failed to update poll message status to processed", log.Fields{
			types.LogFieldKeys.MessageID: request.Id,
			types.LogFieldKeys.Error:     err,
		})
	} else {
		logger.Info("Poll message processed successfully", log.Fields{
			types.LogFieldKeys.MessageID: request.Id,
		})
	}
	return
}
