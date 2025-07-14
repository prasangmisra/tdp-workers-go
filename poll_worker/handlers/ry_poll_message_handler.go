package handlers

import (
	"errors"

	sqlx "github.com/jmoiron/sqlx/types"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	tcwire "github.com/tucowsinc/tdp-messages-go/message"
	"github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"

	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// RyPollMessageHandler a callback handler for the registry notification and insert it to database
func (service *WorkerService) RyPollMessageHandler(server messagebus.Server, message proto.Message) error {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "RyPollMessageHandler")
	defer service.tracer.FinishSpan(span)

	// Accreditation
	accreditation := server.Headers()["accreditation"].(string)
	if accreditation == "" {
		log.Error("Missing accreditation header")
		return server.ErrorReply(tcwire.ErrorResponse_FAILED_PRECONDITION, "accreditation is missing", "", false, message)
	}

	// We need to type-cast the proto.Message to the wanted type
	request := message.(*ryinterface.EppPollMessage)

	log.Debug("Received poll message", log.Fields{
		types.LogFieldKeys.MessageID: request.Id,
		LogFieldKeys.Accreditation:   accreditation,
	})
	// Insert poll message into db
	pollMessage := service.ToPollMessage(request, accreditation)
	err := service.db.CreatePollMessage(ctx, pollMessage)
	if err != nil {
		if errors.Is(err, database.ErrPollMessageInsert) {
			service.bus.Ack(server.Envelope().Id, true) // Send NACK message to RMQ
		}
		log.Error("Error inserting the poll message into the database", log.Fields{
			types.LogFieldKeys.MessageID: request.Id,
			types.LogFieldKeys.Error:     err,
		})
	}
	log.Info("Poll message successfully inserted", log.Fields{
		types.LogFieldKeys.MessageID: request.Id,
		LogFieldKeys.Accreditation:   accreditation,
	})

	_ = server.Reply(&common.SuccessResponse{}, nil)

	return nil
}

// ToPollMessage Converts the received ryinterface.EppPollMessage to an PollMessage model
func (service *WorkerService) ToPollMessage(message *ryinterface.EppPollMessage, accreditation string) (pollMessage *model.PollMessage) {

	// Set message lang
	var messageLang *string
	if message.GetLang() == "" {
		messageLang = nil
	} else {
		messageLang = message.Lang
	}

	// Poll Message
	pollMessage = &model.PollMessage{
		Accreditation: accreditation,
		EppMessageID:  message.Id,
		Msg:           message.Msg,
		Lang:          messageLang,
		QueueDate:     types.TimestampToTime(message.QueueDate),
		CreatedDate:   types.TimestampToTime(timestamppb.Now()),
	}

	// Message type and data
	var msgType string
	var msgData sqlx.JSONText
	switch {
	case message.GetTrnData() != nil:
		msgType = "transfer"
		msgData, _ = protojson.Marshal(message.GetTrnData())
	case message.GetRenData() != nil:
		msgType = "renewal"
		msgData, _ = protojson.Marshal(message.GetRenData())
	case message.GetPanData() != nil:
		msgType = "pending_action"
		msgData, _ = protojson.Marshal(message.GetPanData())
	case message.GetDomainData() != nil:
		msgType = "domain_info"
		msgData, _ = protojson.Marshal(message.GetDomainData())
	case message.GetContactData() != nil:
		msgType = "contact_info"
		msgData, _ = protojson.Marshal(message.GetContactData())
	case message.GetHostData() != nil:
		msgType = "host_info"
		msgData, _ = protojson.Marshal(message.GetHostData())
	default:
		msgType = "unspec"
		msgData = nil
	}

	pollMessage.TypeID = service.db.GetPollMessageTypeId(msgType)
	pollMessage.Data = &msgData

	return
}
