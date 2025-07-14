package handler

import (
	"fmt"

	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/worker"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// DBPollMessageHandler converts database poll message into proto message
func (s *WorkerService) DBPollMessageHandler(row *model.PollMessage) (proto.Message, error) {
	msgType := s.db.GetPollMessageTypeName(row.TypeID)
	msgData := types.SafeDeref(row.Data)

	pollMsg := &worker.PollMessage{
		Id:            row.ID,
		Msg:           types.SafeDeref(row.Msg),
		Type:          msgType,
		Status:        s.db.GetPollMessageStatusName(row.StatusID),
		Accreditation: row.Accreditation,
		CreatedDate:   types.ToTimestampMsg(row.CreatedDate),
	}

	var err error

	switch msgType {
	case PollMessageType.Transfer:

		data := &ryinterface.EppPollTrnData{}
		err = protojson.Unmarshal(msgData, data)
		pollMsg.Data = &worker.PollMessage_TrnData{
			TrnData: data,
		}
	case PollMessageType.Renewal:

		data := &ryinterface.EppPollRenData{}
		err = protojson.Unmarshal(msgData, data)
		pollMsg.Data = &worker.PollMessage_RenData{
			RenData: data,
		}
	case PollMessageType.PendingAction:

		data := &ryinterface.EppPollPanData{}
		err = protojson.Unmarshal(msgData, data)
		pollMsg.Data = &worker.PollMessage_PanData{
			PanData: data,
		}
	case PollMessageType.DomainInfo:

		data := &ryinterface.DomainInfoResponse{}
		err = protojson.Unmarshal(msgData, data)
		pollMsg.Data = &worker.PollMessage_DomainData{
			DomainData: data,
		}
	case PollMessageType.ContactInfo:

		data := &ryinterface.ContactInfoResponse{}
		err = protojson.Unmarshal(msgData, data)
		pollMsg.Data = &worker.PollMessage_ContactData{
			ContactData: data,
		}
	case PollMessageType.HostInfo:

		data := &ryinterface.HostInfoResponse{}
		err = protojson.Unmarshal(msgData, data)
		pollMsg.Data = &worker.PollMessage_HostData{
			HostData: data,
		}
	case PollMessageType.Unspec:

		pollMsg.Data = nil
	default:

		err = fmt.Errorf("unknown message type: %s", msgType)
	}

	return pollMsg, err
}
