package handlers

import (
	"context"
	"encoding/json"
	"net"
	"strconv"
	"strings"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

var lookupIP = net.LookupIP

// HostProvisionHandler() This is a callback handler for the HostProvision event
// and is in charge of sending the request to the registry interface
func (service *WorkerService) HostProvisionHandler(server messagebus.Server, message proto.Message) error {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "HostProvisionHandler")
	defer service.tracer.FinishSpan(span)

	// we need to type-cast the proto.Message to the wanted type
	request := message.(*job.Notification)
	jobId := request.GetJobId()

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: jobId,
	})

	logger.Info("Starting HostProvisionHandler for the job")

	data := new(types.HostData)

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

		logger.Info("Starting host provision job processing")

		if job.StatusID != tx.GetJobStatusId(types.JobStatus.Submitted) {
			logger.Error(types.LogMessages.UnexpectedJobStatus, log.Fields{
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

		// Get the host addresses based on the host accreditation
		ipList := service.setHostIpAddresses(ctx, data)

		msg := ryinterface.HostCreateRequest{
			Name:      data.HostName,
			Addresses: ipList,
		}

		queue := types.GetTransformQueue(data.Accreditation.AccreditationName)
		headers := map[string]any{
			"reply_to":       "WorkerJobHostProvisionUpdate",
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
			types.LogFieldKeys.Host:                 data.HostName,
			"addresses":                             strings.Join(ipList, ", "),
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

func (s *WorkerService) setHostIpAddresses(ctx context.Context, data *types.HostData) (ipList []string) {
	ipList = data.HostAddrs

	// host tld is not managed by accreditation
	// ip addresses passed in order should not be used
	if data.HostAccreditationTld.AccreditationId != data.Accreditation.AccreditationId {
		ipList = []string{}

		// ip addresses might still be required by registry
		if data.HostIpRequiredNonAuth {
			ips, err := lookupIP(data.HostName)
			if err != nil {
				return
			}

			tldSetting, err := s.db.GetTLDSetting(ctx, data.HostAccreditationTld.AccreditationTldId, "tld.dns.ipv6_support")
			if err != nil {
				return
			}

			isIpv6Supported, err := strconv.ParseBool(tldSetting.Value)
			if err != nil {
				return
			}

			for _, ip := range ips {
				if !isIpv6Supported && ip.To4() == nil {
					continue
				} else {
					ipList = append(ipList, ip.String())
				}
			}
		}
	}

	return
}
