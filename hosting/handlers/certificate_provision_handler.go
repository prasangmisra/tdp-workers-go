package handlers

import (
	"context"
	"encoding/json"
	"errors"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-workers-go/pkg/certificate"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

func (service *WorkerService) HostingCertificateProvisionHandler(server messagebus.Server, message proto.Message) (err error) {
	ctx := server.Context()

	request := message.(*job.Notification)
	jobId := request.GetJobId()

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: jobId,
	})

	logger.Info("Starting HostingCertificateProvisionHandler for the job")

	data := new(types.HostingCertificateData)

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

		logger.Info("Starting hosting certificate provision job processing")

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

		logger = log.CreateChildLogger(log.Fields{types.LogFieldKeys.Metadata: data.Metadata})

		// set job as processing for now; and conditionally completed when we get res from api
		// but what to do if api is unavailable?
		err = tx.SetJobStatus(ctx, job, types.JobStatus.Processing, nil)
		if err != nil {
			logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

		err = service.createCertificate(ctx, data)
		if err != nil {
			switch {
			case errors.Is(err, ErrorCertificateExists):
				res, getErr := service.getCertificate(ctx, data.DomainName)
				if getErr != nil {
					if errors.Is(err, ErrorClientTimeout) {
						logger.Error("Error getting existing certificate: request timeout", log.Fields{
							types.LogFieldKeys.Error: err,
						})
						tx.Rollback()
						return nil
					}

					logger.Error("Error getting existing certificate", log.Fields{
						types.LogFieldKeys.Error: getErr,
					})
					resMsg := getErr.Error()
					job.ResultMessage = &resMsg
					return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
				}

				notBefore, notAfter := certificate.GetCertificateValidDates(res.Cert)
				if notBefore == nil || notAfter == nil {
					logger.Error("Error getting valid dates for existing certificate")
					return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
				}

				provisionRecord, provisionErr := tx.GetProvisionHostingCertififcate(ctx, &model.ProvisionHostingCertificateCreate{
					HostingID: data.RequestId,
				})

				if provisionErr != nil {
					logger.Error("Error getting provision record", log.Fields{
						types.LogFieldKeys.Error: provisionErr,
					})
					resMsg := provisionErr.Error()
					job.ResultMessage = &resMsg
					return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
				}

				provisionRecord.Body = &res.Cert
				provisionRecord.Chain = &res.Chain
				provisionRecord.PrivateKey = &res.Privkey
				provisionRecord.NotBefore = notBefore
				provisionRecord.NotAfter = notAfter
				provisionRecord.StatusID = tx.GetProvisionStatusId(types.ProvisionStatus.Completed)

				tx.UpdateProvisionHostingCertificate(ctx, provisionRecord)

				logger.Info(types.LogMessages.JobProcessingCompleted)
				// update the record with the result data
				// weird one here. response is struct not protomessage.
				// leave jrd as nil?
				return tx.SetJobStatus(ctx, job, types.JobStatus.Completed, nil)

			// incase of retry-able error; we can rollback the transaction and
			// the job will be retried

			// check what we can do if the certificate already exists and the
			// request to get the existing certificate fails

			// in this case the request has been retried as a result of the error,
			// and the retries have not been successful

			case errors.Is(err, ErrorClientTimeout):
				// rollback the transaction and the job will be retried
				logger.Error("Error creating certificate; job will be retried", log.Fields{
					types.LogFieldKeys.Error: err,
				})
				tx.Rollback()
				return

			default:
				logger.Error("Error creating certificate", log.Fields{
					types.LogFieldKeys.Error: err,
				})
				resMsg := err.Error()
				job.ResultMessage = &resMsg
				return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
			}
		}

		// if successful, set job status to conditionally completed
		logger.Info(types.LogMessages.JobProcessingCompleted)
		return tx.SetJobStatus(ctx, job, types.JobStatus.CompletedConditionally, nil)
	})
}

func (service *WorkerService) createCertificate(ctx context.Context, data *types.HostingCertificateData) (err error) {
	ctx, cancel := context.WithTimeout(ctx, service.CertBotApiTimeout)
	defer cancel()

	_, err = service.certificateApi.CreateCertificate(ctx, CreateCertificateRequest{
		Domain:    data.DomainName,
		RequestId: data.RequestId,
	},
	)

	select {
	case <-ctx.Done():
		err = errorSelector(err)
	default:
	}

	return
}

func (service *WorkerService) getCertificate(ctx context.Context, domainName string) (res *GetCertificateResponse, err error) {
	ctx, cancel := context.WithTimeout(ctx, service.CertBotApiTimeout)
	defer cancel()

	res, err = service.certificateApi.GetCertificate(ctx, domainName)

	select {
	case <-ctx.Done():
		err = errorSelector(err)
	default:
	}

	return
}

func errorSelector(err error) error {
	if err != nil {
		switch {
		case errors.Is(err, ErrorCertificateExists):
			return ErrorCertificateExists
		default:
			return ErrorClientTimeout
		}
	}
	return nil
}
