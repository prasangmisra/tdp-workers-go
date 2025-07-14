package handlers

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/google/uuid"
	tcwire "github.com/tucowsinc/tdp-messages-go/message"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/worker"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type AutoRenewHandler struct{}

func NewAutoRenewHandler() *AutoRenewHandler {
	return &AutoRenewHandler{}
}

func (a *AutoRenewHandler) Matches(msg *worker.PollMessage) bool {
	if msg.Type == PollMessageType.Renewal {
		return true
	}
	for _, pattern := range UnspecPollMessageTypePatternMap[PollMessageType.Renewal] {
		if strings.Contains(msg.Msg, pattern) {
			return true
		}
	}
	return false
}

func (a *AutoRenewHandler) Handle(ctx context.Context, service *WorkerService, request *worker.PollMessage) (err error) {
	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.LogID:     uuid.NewString(),
		LogFieldKeys.PollMessageID:   request.Id,
		LogFieldKeys.PollMessageType: request.Type,
		LogFieldKeys.Accreditation:   request.Accreditation,
	})

	// Get domain name
	domainName := GetDomainName(request)
	if domainName == "" {
		err = fmt.Errorf("no domain name found in received poll message")
		logger.Error("No domain name found", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	// Get domain
	domain, err := service.db.GetDomain(ctx, &model.Domain{Name: domainName})
	if err != nil {
		if errors.Is(err, database.ErrNotFound) {
			logger.Error("No domain record found for domain name", log.Fields{
				types.LogFieldKeys.Domain: domainName,
			})
			return
		}

		logger.Error("Error getting domain details from database", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	// Get domain expiry date
	exDate, err := GetDomainExpiryDate(service, ctx, request, domainName, logger)
	if err != nil {
		logger.Error("Error getting domain expiry date", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	// Domain model
	d := model.Domain{
		ID:           domain.ID,
		RyExpiryDate: *types.TimestampToTime(exDate),
		ExpiryDate:   *types.TimestampToTime(exDate),
	}

	// Update domain expiry date
	err = service.db.UpdateDomain(ctx, &d)
	if err != nil {
		logger.Error("Error updating domain details in database", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	// Domain rgp status model
	drs := model.DomainRgpStatus{
		DomainID: domain.ID,
		StatusID: service.db.GetRgpStatusId("autorenew_grace_period"),
	}

	// Create domain rgp status
	err = service.db.CreateDomainRgpStatus(ctx, &drs)
	if err != nil {
		logger.Error("Error inserting domain RGP status in database", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	logger.Info("Successfully handled auto-renew for domain", log.Fields{
		types.LogFieldKeys.Domain: domainName,
	})

	return
}

// GetDomainExpiryDate gets expiry date from renewal poll message type or fetches from domain info request
func GetDomainExpiryDate(service *WorkerService, ctx context.Context, request *worker.PollMessage, domainName string, logger logger.ILogger) (exDate *timestamppb.Timestamp, err error) {

	if request.GetRenData() != nil && request.GetRenData().ExDate != nil {
		exDate = request.GetRenData().ExDate
	} else {
		msg := &ryinterface.DomainInfoRequest{Name: domainName}
		queue := types.GetQueryQueue(request.Accreditation)
		headers := map[string]any{}

		response, rpcErr := service.bus.Call(ctx, queue, msg, headers)
		if rpcErr != nil {
			logger.Error("Error sending domain info message", log.Fields{
				types.LogFieldKeys.Error: rpcErr,
			})
			err = ErrTempRyFailure
			return
		}

		switch m := response.Message.(type) {
		case *ryinterface.DomainInfoResponse:
			exDate = m.ExpiryDate
		case *tcwire.ErrorResponse:
			logger.Error("Error response received", log.Fields{
				types.LogFieldKeys.Response: m.GetMessage(),
			})
			err = ErrTempRyFailure
			return
		default:
			err = fmt.Errorf("unexpected message type received for domain info response: %v", response.Message)
			logger.Error("Unexpected message type received", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}
	}

	return
}
