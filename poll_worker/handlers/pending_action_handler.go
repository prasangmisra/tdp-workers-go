package handlers

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/tucowsinc/tdp-messages-go/message/worker"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

type PendingActionHandler struct{}

func NewPendingActionHandler() *PendingActionHandler {
	return &PendingActionHandler{}
}

func (a *PendingActionHandler) Matches(msg *worker.PollMessage) bool {
	if msg.Type == PollMessageType.PendingAction {
		return true
	}

	for _, pattern := range UnspecPollMessageTypePatternMap[PollMessageType.PendingAction] {
		if strings.Contains(msg.Msg, pattern) {
			return true
		}
	}
	return false
}

func (a *PendingActionHandler) Handle(ctx context.Context, service *WorkerService, request *worker.PollMessage, logger logger.ILogger) (err error) {

	// Get domain name
	domainName := GetDomainName(request)
	if domainName == "" {
		err = fmt.Errorf("no domain name found in received poll message")
		logger.Error("No domain name found", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	// Status id
	statusId := service.db.GetProvisionStatusId("pending_action")

	// Provision domain model
	vpd := &model.VProvisionDomain{
		AccreditationName: &request.Accreditation,
		DomainName:        &domainName,
		StatusID:          &statusId,
	}

	// Client transaction id
	if request.GetPanData() != nil && request.GetPanData().PaCltrid != "" {
		vpd.RyCltrid = &request.GetPanData().PaCltrid
	}

	// Get provision domain
	pd, err := service.db.GetVProvisionDomain(ctx, vpd)
	if err != nil {
		if errors.Is(err, database.ErrNotFound) {
			logger.Warn("No pending provision domain record found for poll message", log.Fields{
				types.LogFieldKeys.Domain: domainName,
			})
			return nil
		}

		logger.Error("Error looking up pending provision domain record in database", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	// New provision status
	targetStatus := GetPendingActionTargetStatus(request)

	// Update provision status
	err = service.db.SetProvisionDomainStatus(ctx, *pd.ID, targetStatus)
	if err == nil {
		logger.Error("Error updating provision domain status", log.Fields{
			types.LogFieldKeys.Domain: domainName,
			types.LogFieldKeys.Status: targetStatus,
			types.LogFieldKeys.Error:  err,
		})
		return
	}

	logger.Info("Successfully processed pending action poll message", log.Fields{
		types.LogFieldKeys.Domain: domainName,
		types.LogFieldKeys.Status: targetStatus,
	})

	return
}

func GetPendingActionTargetStatus(request *worker.PollMessage) (targetStatus string) {
	if request.Type == PollMessageType.Unspec && strings.Contains(request.Msg, "Completed") {
		targetStatus = "completed"
	} else if request.GetPanData() != nil && request.GetPanData().PaResult == 1 {
		targetStatus = "completed"
	} else {
		targetStatus = "failed"
	}
	return
}
