package handlers

import (
	"encoding/json"
	"fmt"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-shared-go/dns"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

const acmeChallengeFormat = "_acme-challenge.%s"

func (service *WorkerService) DNSCheckHandler(s messagebus.Server, m proto.Message) (err error) {
	ctx := s.Context()

	request := m.(*job.Notification)
	jobId := request.GetJobId()

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: jobId,
	})

	logger.Info("Starting DNSCheckHandler for the job")

	data := new(types.DNSCheckData)

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

		logger.Info("Starting DNS check job processing")

		if job.StatusID != tx.GetJobStatusId(types.JobStatus.Submitted) {
			logger.Error(types.LogMessages.UnexpectedJobStatus, log.Fields{
				types.LogFieldKeys.Status: job.Info.JobStatusName,
			})
			return
		}

		// lock job
		err = tx.SetJobStatus(ctx, job, types.JobStatus.Processing, nil)
		if err != nil {
			logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
				types.LogFieldKeys.Error: err,
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

		logger = log.CreateChildLogger(log.Fields{types.LogFieldKeys.Metadata: data.Metadata})

		// perform cname check
		// update job with results
		challengeDomain := fmt.Sprintf(acmeChallengeFormat, data.DomainName)

		// what is this server going to be?
		res, err := service.resolver.Resolve(ctx, challengeDomain, dns.RecordTypes.CNAME)

		if err != nil {
			logger.Error("Error resolving CNAME", log.Fields{
				types.LogFieldKeys.Domain: data.DomainName,
				types.LogFieldKeys.Error:  err,
			})
			resMsg := err.Error()
			job.ResultMessage = &resMsg
			return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
		}

		if len(res) == 0 {
			resMsg := "no CNAME records found"
			logger.Error(resMsg, log.Fields{
				types.LogFieldKeys.Domain: data.DomainName,
			})
			job.ResultMessage = &resMsg
			return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
		}

		// loop through res messages and look for correct one

		target := fmt.Sprintf("%s.%s.", data.DomainName, service.ACMEChallengeDomain)

		for _, record := range res {
			// should we do case insensitive check?
			if target == record.Value {
				logger.Info("CNAME record found", log.Fields{
					types.LogFieldKeys.Domain: data.DomainName,
					"value":                   record.Value,
				})
				// doublecheck what needs to be done here, just mark as completed?
				return tx.SetJobStatus(ctx, job, types.JobStatus.Completed, nil)
			}
			logger.Debug("CNAME record does not match expected value", log.Fields{
				"record":   record.Value,
				"expected": target,
			})
		}

		// if we fell through to here then fail the job
		resMsg := "No matching CNAME records found"
		logger.Error(resMsg, log.Fields{
			types.LogFieldKeys.Domain: data.DomainName,
			"value":                   target,
		})
		job.ResultMessage = &resMsg
		return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
	})
}
