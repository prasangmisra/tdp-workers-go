package handlers

import (
	"context"
	"fmt"
	"strings"

	"github.com/google/uuid"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

const DefaultPurgeableDomainsBatchSize = 100

func (s *CronService) ProcessDomainsPurge(ctx context.Context) error {
	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CronType: "DomainsPurge",
		types.LogFieldKeys.LogID:    uuid.NewString(),
	})

	logger.Info("Starting domain purge process")

	domains, err := s.db.GetPurgeableDomains(ctx, DefaultPurgeableDomainsBatchSize)
	if err != nil {
		logger.Error("Failed to get purgeable domains", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return fmt.Errorf("failed to get purgeable domains: %w", err)
	}

	logger.Info("Fetched purgeable domains", log.Fields{
		"count": len(domains),
	})
	if len(domains) == 0 {
		log.Info("No domains to purge")
		return nil
	}

	for _, d := range domains {
		logger.Info("Processing domain", log.Fields{
			types.LogFieldKeys.Domain:   *d.Name,
			types.LogFieldKeys.DomainID: *d.ID,
		})

		if err = s.processDomainPurge(ctx, d, logger); err != nil {
			logger.Error("Error processing domain purge", log.Fields{
				types.LogFieldKeys.Domain:   *d.Name,
				types.LogFieldKeys.DomainID: *d.ID,
				types.LogFieldKeys.Error:    err,
			})
		} else {
			logger.Info("Successfully processed domain purge", log.Fields{
				types.LogFieldKeys.Domain:   *d.Name,
				types.LogFieldKeys.DomainID: *d.ID,
			})
		}
	}

	log.Info("Done processing domains purge", log.Fields{"domains": len(domains)})

	return nil
}

func (s *CronService) processDomainPurge(ctx context.Context, domain model.VDomain, domainLogger logger.ILogger) error {
	domainName := *domain.Name

	acc, err := s.db.GetDomainAccreditation(ctx, domainName)
	if err != nil {
		domainLogger.Error("Error fetching domain accreditation", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return fmt.Errorf("error getting accreditation by id: %w", err)
	}

	domainInfoResp, err := s.getDomainInfo(ctx, domainName, &acc.Accreditation)
	if err != nil {
		domainLogger.Error("Error fetching domain info", log.Fields{
			types.LogFieldKeys.Domain: domainName,
			types.LogFieldKeys.Error:  err,
		})
		return fmt.Errorf("error getting domain info for domain[%s]: %w", domainName, err)
	}

	response := domainInfoResp.GetRegistryResponse()
	if response.GetEppCode() != types.EppCode.Success {
		if response.GetEppCode() == types.EppCode.ObjectDoesNotExist ||
			strings.Contains(strings.ToLower(response.GetEppMessage()), "object does not exist") ||
			strings.Contains(strings.ToLower(response.GetEppMessage()), "object not found") {

			domainLogger.Warn("Domain does not exist. Deleting domain record", log.Fields{
				types.LogFieldKeys.Domain: domainName,
			})
			return s.deleteDomain(ctx, *domain.ID, domainLogger)
		}

		domainLogger.Error("Error fetching domain info from registry", log.Fields{
			types.LogFieldKeys.Domain: domainName,
			types.LogFieldKeys.Error:  response.GetEppMessage(),
		})
		return fmt.Errorf("error getting domain info from registry for domain[%s]: %s", domainName, response.GetEppMessage())
	}

	if acc.RegistrarID != domainInfoResp.Clid {
		domainLogger.Warn("Registrar ID mismatch. Deleting domain record", log.Fields{
			types.LogFieldKeys.Domain: domainName,
		})
		return s.deleteDomain(ctx, *domain.ID, domainLogger)
	}
	domainLogger.Info("Domain accreditation and registrar match", log.Fields{
		types.LogFieldKeys.Domain: domainName,
	})
	return nil
}

func (s *CronService) deleteDomain(ctx context.Context, domainId string, domainLogger logger.ILogger) error {
	domainLogger.Info("Deleting domain record", log.Fields{
		types.LogFieldKeys.DomainID: domainId,
	})
	if err := s.db.DeleteDomainWithReason(ctx, domainId, "deleted"); err != nil {
		domainLogger.Error("Error deleting domain record", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return err
	}
	domainLogger.Info("Domain record deleted successfully", log.Fields{
		types.LogFieldKeys.DomainID: domainId,
	})
	return nil
}
