package handlers

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/lib/pq"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension"
	"github.com/tucowsinc/tdp-shared-go/logger"

	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/epp_utils"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// RyDomainTransferInHandler receives the responses from the registry interface
// and updates the database
func (service *WorkerService) RyDomainTransferInHandler(server messagebus.Server, message proto.Message, job *model.Job, tx database.Database, logger logger.ILogger) (err error) {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "RyDomainTransferInHandler")
	defer service.tracer.FinishSpan(span)

	response := message.(*ryinterface.DomainInfoResponse)

	logger.Debug(types.LogMessages.ReceivedResponseFromRY, log.Fields{
		types.LogFieldKeys.Response: response.String(),
	})

	data := new(types.DomainTransferInData)

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

	registryResponse := response.GetRegistryResponse()

	jrd := types.JobResultData{Message: message}

	if registryResponse.GetIsSuccess() {
		var hosts pq.StringArray
		for _, h := range response.Hosts {
			hosts = append(hosts, h)
		}

		pdti := model.ProvisionDomainTransferIn{
			ID:               data.ProvisionDomainTransferInId,
			RyCreatedDate:    types.TimestampToTime(response.GetCreatedDate()),
			RyExpiryDate:     types.TimestampToTime(response.GetExpiryDate()),
			RyTransferedDate: types.TimestampToTime(response.GetTransferredDate()),
			Hosts:            &hosts,
		}
		err = processExtensions(ctx, tx, &pdti, response.GetExtensions())
		if err != nil {
			logger.Error("Error processing extensions in post-transfer domain info response", log.Fields{
				types.LogFieldKeys.Error: err,
			})

			job.ResultMessage = types.ToPointer("Failed to handle extensions for transferred domain")
			err = tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
			if err != nil {
				logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
					types.LogFieldKeys.Error: err,
				})
			}
			return
		}

		err = tx.UpdateProvisionDomainTransferIn(ctx, &pdti)
		if err != nil {
			logger.Error("Error updating provision_domain_transfer_in with results", log.Fields{
				types.LogFieldKeys.Error: err,
			})

			resMsg := err.Error()
			job.ResultMessage = &resMsg
			err = tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
			if err != nil {
				logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
					types.LogFieldKeys.Error: err,
				})
			}
			return
		}

		err = tx.SetJobStatus(ctx, job, types.JobStatus.Completed, &jrd)
		if err != nil {
			logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
		}
	} else {
		logger.Error("Domain failed to transfer in on the registry backend", log.Fields{
			types.LogFieldKeys.Domain:      data.Name,
			types.LogFieldKeys.EppCode:     registryResponse.GetEppCode(),
			types.LogFieldKeys.EppMessage:  registryResponse.GetEppMessage(),
			types.LogFieldKeys.XmlResponse: registryResponse.GetXml(),
		})

		epp_utils.SetJobErrorFromRegistryResponse(registryResponse, job, &jrd)
		err = tx.SetJobStatus(ctx, job, types.JobStatus.Failed, &jrd)
		if err != nil {
			logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
		}
	}

	return
}

func processExtensions(ctx context.Context, tx database.Database, pdti *model.ProvisionDomainTransferIn, extensions map[string]*anypb.Any) error {
	if len(extensions) == 0 {
		return nil
	}

	for extKey, extValue := range extensions {
		switch extKey {
		case "secdns":
			log.Debug("Found secdns extension in post transfer domain info response", log.Fields{
				"secdns extension": extValue.String(),
			})

			secDnsMsg := new(extension.SecdnsInfoResponse)
			if err := extValue.UnmarshalTo(secDnsMsg); err != nil {
				return fmt.Errorf("failed to unmarshal secdns extension: %w", err)
			}

			switch secDnsData := secDnsMsg.Data.(type) {
			case *extension.SecdnsInfoResponse_DsSet:
				dbDsDataSet := make([]model.TransferInDomainSecdnsDsDatum, len(secDnsData.DsSet.DsData))
				for i, dsData := range secDnsData.DsSet.DsData {
					dbDsDataSet[i] = model.TransferInDomainSecdnsDsDatum{
						Algorithm:                   dsData.Alg,
						KeyTag:                      dsData.KeyTag,
						DigestType:                  dsData.DigestType,
						Digest:                      dsData.Digest,
						ProvisionDomainTransferInID: pdti.ID,
					}
					// TODO: handle keyData: it's not yet supported
				}
				pdti.SecdnsType = types.ToPointer("ds_data")

				if err := tx.CreateDsDataSet(ctx, dbDsDataSet); err != nil {
					return fmt.Errorf("failed to create ds data set: %w", err)
				}

			case *extension.SecdnsInfoResponse_KeySet:
				dbKeyDataSet := make([]model.TransferInDomainSecdnsKeyDatum, len(secDnsData.KeySet.KeyData))
				for i, keyData := range secDnsData.KeySet.KeyData {
					dbKeyDataSet[i] = model.TransferInDomainSecdnsKeyDatum{
						Algorithm:                   keyData.Alg,
						Flags:                       keyData.Flags,
						Protocol:                    keyData.Protocol,
						PublicKey:                   keyData.PubKey,
						ProvisionDomainTransferInID: pdti.ID,
					}
				}

				pdti.SecdnsType = types.ToPointer("key_data")

				if err := tx.CreateKeyDataSet(ctx, dbKeyDataSet); err != nil {
					return fmt.Errorf("failed to create key data set: %w", err)
				}

			default:
				return fmt.Errorf("unsupported secdns extension data type: %T", secDnsData)
			}
		case "idn":
			log.Debug("Found idn extension in post transfer domain info response", log.Fields{
				"idn extension": extValue.String()},
			)

			idnMsg := new(extension.IdnInfoResponse)
			if err := extValue.UnmarshalTo(idnMsg); err != nil {
				return fmt.Errorf("failed to unmarshal idn extension: %w", err)
			}
			pdti.Uname = &idnMsg.Uname
			pdti.Language = &idnMsg.Table
		}
	}

	return nil
}
