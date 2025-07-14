package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"google.golang.org/protobuf/proto"

	"github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/epp_utils"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

var feeTypeMap = map[string]ryinterface.DomainOperationFee_BaseOperation{
	"transfer_in": ryinterface.DomainOperationFee_TRANSFER,
	"renew":       ryinterface.DomainOperationFee_RENEWAL,
	"redeem":      ryinterface.DomainOperationFee_RESTORE,
	"create":      ryinterface.DomainOperationFee_REGISTRATION,
}

// RyValidateDomainCheckHandler receives the domain check responses from the registry interface
// and updates the database
func RyValidateDomainCheckHandler(ctx context.Context, response *ryinterface.DomainCheckResponse, job *model.Job, tx database.Database, logger logger.ILogger) (err error) {
	data := new(types.DomainCheckValidationData)

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

	jrd := types.JobResultData{Message: response}

	jobStatus := types.JobStatus.Completed

	if !registryResponse.GetIsSuccess() {
		logger.Error("Error checking domain at registry", log.Fields{
			types.LogFieldKeys.Domain:      data.Name,
			types.LogFieldKeys.EppCode:     registryResponse.GetEppCode(),
			types.LogFieldKeys.EppMessage:  registryResponse.GetEppMessage(),
			types.LogFieldKeys.XmlResponse: registryResponse.GetXml(),
		})

		epp_utils.SetJobErrorFromRegistryResponse(registryResponse, job, &jrd)
		jobStatus = types.JobStatus.Failed
	} else if len(response.Domains) != 1 {
		logger.Error("Invalid domain check response received", log.Fields{})

		resMsg := "domain validation failed"
		job.ResultMessage = &resMsg
		jobStatus = types.JobStatus.Failed
	} else {
		domain := response.Domains[0]

		if data.OrderType == types.DomainOrderType.Create && !domain.IsAvailable {
			logger.Error("Domain validation failed; domain is not available", log.Fields{})

			resMsg := "domain is not available"
			job.ResultMessage = &resMsg
			jobStatus = types.JobStatus.Failed
		}

		err = handleCheckResponse(domain, data, logger)
		if err != nil {
			logger.Error("Invalid premium operation", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			resMsg := err.Error()
			job.ResultMessage = &resMsg
			jobStatus = types.JobStatus.Failed
		}
	}

	err = tx.SetJobStatus(ctx, job, jobStatus, &jrd)
	if err != nil {
		logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}

	return
}

// isPremiumDomain checks if the domain is premium based on the pricing tier
func isPremiumDomain(tier *string) bool {
	return tier != nil && (*tier == "Premium" ||
		strings.Contains(*tier, "premium") ||
		strings.Contains(*tier, "default tier legacy"))
}

// handleResponse validates response against premium tld settings + price
func handleCheckResponse(domain *ryinterface.DomainAvailResponse, data *types.DomainCheckValidationData, logger logger.ILogger) (err error) {
	var price *common.Money

	// not a premium domain, success for now (needs sku price check)
	if !isPremiumDomain(domain.PricingTier) {
		return
	}

	// premium domain not enabled, fail
	if !data.PremiumDomainEnabled {
		return errors.New("premium domain not enabled")
	}

	if data.PremiumOperation != nil && *data.PremiumOperation {
		price, err = getDomainOperationPrice(domain.Fees, data.OrderType)
		if err != nil {
			logger.Error("Error getting domain operation price", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return errors.New("error getting domain operation price")
		}

		if data.Price != nil && proto.Equal(types.ToMoneyMsg(data.Price), price) {
			// success
			return
		}
		// fail (price mismatch)
		return errors.New("price mismatch")
	}

	// operation not premium, success for now (needs sku price check)
	return
}

func getDomainOperationPrice(fees []*ryinterface.DomainOperationFee, operation string) (price *common.Money, err error) {
	if len(fees) == 0 {
		return
	}

	targetFeeType, exists := feeTypeMap[operation]
	if !exists {
		return nil, fmt.Errorf("unknown operation type: %s", operation)
	}

	for _, fee := range fees {
		// operation can have different fees for different phases,
		// for now we only care about fee for the operation without phase
		if fee.Operation == targetFeeType && fee.Phase == nil {
			if price == nil {
				price = fee.Price
				continue
			}

			price, err = types.AddMoney(price, fee.Price)
			if err != nil {
				return
			}
		}
	}
	return
}
