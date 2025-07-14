package handlers

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// DomainRedeemReportHandler This is a callback handler for the DomainRedeemReport event
// and is in charge of sending the request to the registry interface
func (service *WorkerService) DomainRedeemReportHandler(server messagebus.Server, message proto.Message) error {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "DomainRedeemReportHandler")
	defer service.tracer.FinishSpan(span)

	// we need to type-cast the proto.Message to the wanted type
	request := message.(*job.Notification)
	jobId := request.GetJobId()

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: jobId,
	})

	logger.Debug("Starting DomainRedeemReportHandler for the job")

	data := new(types.DomainRedeemData)

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

		logger.Info("Starting domain redeem report job processing")

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

		msg, err := toDomainRedeemReport(*data, logger)
		if err != nil {
			logger.Error("Failed to create domain redeem report", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			resMsg := err.Error()
			job.ResultMessage = &resMsg
			return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
		}

		queue := types.GetTransformQueue(data.Accreditation.AccreditationName)
		headers := map[string]any{
			"reply_to":       "WorkerJobDomainProvisionUpdate",
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
			types.LogFieldKeys.Domain:               data.Name,
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

func formatDomainRedeemData(item types.DomainRedeemData, logger logger.ILogger) string {
	logger.Debug("Redeem order item", log.Fields{
		types.LogFieldKeys.Domain: item.Name,
	})

	builder := strings.Builder{}
	addField := func(format string, value ...interface{}) {
		builder.WriteString(fmt.Sprintf(format, value))
	}

	addField("name:%s\n", item.Name)
	addField("status s=\"%s\"\n", item.Status)
	for _, contact := range item.Contacts {
		if contact.Type == "registrant" {
			addField("%s:%s\n", contact.Type, contact.Handle)
		} else {
			addField("contact type %s:%s\n", contact.Type, contact.Handle)
		}
	}

	for _, nameserver := range item.Nameservers {
		addField("ns:%s\n", nameserver.Name)
	}
	addField("crDate:%s\n", item.CreateDate)
	addField("exDate:%s\n", item.ExpiryDate)
	result := builder.String()
	log.Debug("Formatted redeem order data", log.Fields{
		types.LogFieldKeys.Domain:  item.Name,
		types.LogFieldKeys.Message: result,
	})
	return result
}

func toDomainRedeemReport(data types.DomainRedeemData, logger logger.ILogger) (msg *ryinterface.DomainUpdateRequest, err error) {
	domainData := formatDomainRedeemData(data, logger)

	rgpExtension := new(extension.RgpUpdateRequest)
	rgpExtension.RgpOp = "report"
	rgpExtension.RgpReport = &extension.RgpUpdateRequest_RgpReport{
		PreData:   domainData,
		PostData:  domainData,
		DelTime:   timestamppb.New(data.DeleteDate),
		ResTime:   timestamppb.New(data.RestoreDate),
		ResReason: types.RedeemRestoreReason,
		Statement1: &extension.RgpUpdateRequest_RgpStatement{
			Statement: types.RedeemStatement1,
		},
		Statement2: &extension.RgpUpdateRequest_RgpStatement{
			Statement: types.RedeemStatement2,
		},
	}

	anyExtension, err := anypb.New(rgpExtension)
	if err != nil {
		logger.Error("Failed to create RGP extension", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return nil, err
	}

	msg = &ryinterface.DomainUpdateRequest{
		Name:       data.Name,
		Extensions: map[string]*anypb.Any{"rgp": anyExtension},
	}

	// if the price is set, we need to add the fee extension
	if data.Price != nil && data.RestoreReportIncludesFeeExt {
		feeExtension, err := anypb.New(&extension.FeeTransformRequest{Fee: []*extension.FeeFee{{Price: types.ToMoneyMsg(data.Price)}}})
		if err != nil {
			logger.Error("Failed to create Fee extension", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return nil, err
		}
		msg.Extensions["fee"] = feeExtension
	}

	logger.Info("Redeem report request created successfully", log.Fields{
		types.LogFieldKeys.Domain: data.Name,
		"extensions_used":         len(msg.Extensions),
	})

	return msg, nil
}
