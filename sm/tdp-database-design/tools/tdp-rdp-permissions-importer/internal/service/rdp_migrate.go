package service

import (
	"context"
	"errors"
	"fmt"

	modelcsv "github.com/tucowsinc/tdp-database-design/tools/tdp-rdp-permissions-importer/internal/model/csv"
	"github.com/tucowsinc/tdp-shared-go/logger"

	"github.com/jackc/pgx/v5"
)

type Permission struct {
	Name      string
	Id        string
	StartDate string
}

// GetValidity returns the validity period for the permission.
func (p *Permission) GetStartDate() string {
	if p.StartDate != "" {
		return p.StartDate
	}
	return "NOW()"
}

func (s *service) MigrateRDPPermissions(ctx context.Context, records []*modelcsv.RDPRecord, tld string) (returnedError error) {
	// Start a DB transaction
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	log := s.log

	// Ensure the transaction is rolled back if an error occurs
	// and committed if no error occurs
	defer func() {
		if returnedError != nil {
			tx.Rollback(ctx)
		} else {
			tx.Commit(ctx)
		}
	}()

	// Fetch TLD ID based on provided TLD name
	var tldId string
	err = tx.QueryRow(ctx, "SELECT id FROM tld WHERE name = $1 LIMIT 1;", tld).Scan(&tldId)
	if err != nil {
		return fmt.Errorf("failed to find TLD [%s]: %w", tld, err)
	}

	for _, record := range records {
		// Get the data element ID using the contact type and element name
		dataElementId, err := s.getDataElementId(ctx, tx, record)
		if err != nil {
			log.Error("failed to get data element", logger.Fields{
				"record": record,
				"error":  err,
			})
			returnedError = err
			return
		}

		// Insert or reuse a domain_data_element row
		domainDataElementId, err := s.getOrCreateDomainDataElement(ctx, tx, dataElementId, tldId, log)
		if err != nil {
			log.Error("failed to insert domain data element", logger.Fields{
				"record": record,
				"error":  err,
			})
			returnedError = err
			return
		}

		permissions := []*Permission{
			{
				Name:      record.Collection,
				StartDate: record.CollectionStartValidity,
			},
			{
				Name:      record.TransmissionRegistry,
				StartDate: record.TransmissionRegistryStartValidity,
			},
			{
				Name:      record.TransmissionEscrow,
				StartDate: record.TransmissionEscrowStartValidity,
			},
			{
				Name: record.DefaultPublication,
			},
			{
				Name: record.AvailableForConsent,
			},
		}

		// Lookup permission IDs for each category in the record
		for _, permission := range permissions {
			permId, err := s.getPermissionId(ctx, tx, permission.Name)
			if err != nil {
				returnedError = err
				return
			}

			permission.Id = permId
		}

		// Prepare a batch insert for domain_data_element_permission
		insertDomainDataElementPermissionQuery := `INSERT INTO domain_data_element_permission(domain_data_element_id, permission_id, validity) VALUES(@domain_data_element_id, @permission_id, tstzrange(@validity_start, 'infinity', '[)'))`
		batch := &pgx.Batch{}
		for _, permission := range permissions {
			if permission.Id == "" {
				continue
			}

			ddepArgs := pgx.NamedArgs{
				"domain_data_element_id": domainDataElementId,
				"permission_id":          permission.Id,
				"validity_start":         permission.GetStartDate(),
			}

			batch.Queue(insertDomainDataElementPermissionQuery, ddepArgs)
		}
		// Execute the batch insert
		results := tx.SendBatch(ctx, batch)
		for _, permission := range permissions {
			if permission.Id == "" {
				continue
			}

			_, err := results.Exec()
			if err != nil {
				log.Error("failed to insert permission for domain data element", logger.Fields{
					"permission_id":          permission.Id,
					"permission_name":        permission.Name,
					"domain_data_element_id": domainDataElementId,
					"error":                  err,
				})
				returnedError = err
				return
			}
		}

		if err := results.Close(); err != nil {
			log.Error("failed to close batch results", logger.Fields{
				"error": err,
			})
			returnedError = err
			return
		}
	}
	log.Info("Migration completed")

	return nil
}

// Fetch data element ID by joining child and parent element names
func (s *service) getDataElementId(ctx context.Context, tx pgx.Tx, record *modelcsv.RDPRecord) (string, error) {
	var deId string
	err := tx.QueryRow(ctx, "SELECT vde.id as data_element_id FROM v_data_element vde WHERE vde.full_name = $1;", record.DataElementPath).Scan(&deId)
	if err != nil {
		return "", fmt.Errorf("failed to find data element: %w", err)
	}
	return deId, nil
}

// Insert a new domain_data_element or return the existing one
func (s *service) getOrCreateDomainDataElement(ctx context.Context, tx pgx.Tx, dataElementId, tldId string, log logger.ILogger) (string, error) {
	var existingId string
	queryCheck := `SELECT id FROM domain_data_element WHERE data_element_id = @data_element_id AND tld_id = @tld_id`
	checkArgs := pgx.NamedArgs{
		"data_element_id": dataElementId,
		"tld_id":          tldId,
	}

	err := tx.QueryRow(ctx, queryCheck, checkArgs).Scan(&existingId)
	if err == nil {
		log.Info("domain data element already exists, returning existing id", logger.Fields{
			"domain_data_element_id": existingId,
		})
		return existingId, nil
	} else if !errors.Is(err, pgx.ErrNoRows) {
		return "", fmt.Errorf("failed to check existing domain data element: %w", err)
	}

	queryInsert := `INSERT INTO domain_data_element(data_element_id, tld_id) VALUES(@data_element_id, @tld_id) RETURNING id`
	insertArgs := pgx.NamedArgs{
		"data_element_id": dataElementId,
		"tld_id":          tldId,
	}

	var domainDataElementId string
	err = tx.QueryRow(ctx, queryInsert, insertArgs).Scan(&domainDataElementId)
	if err != nil {
		return "", fmt.Errorf("failed to insert domain data element: %w", err)
	}
	return domainDataElementId, nil
}

// Fetch permission ID by name
func (s *service) getPermissionId(ctx context.Context, tx pgx.Tx, permissionName string) (string, error) {
	// 🔹 Return from cache if available
	if permissionName == "" {
		return "", nil
	}
	if id, ok := s.permissionCache[permissionName]; ok {
		return id, nil
	}

	var permissionId string
	query := `SELECT id FROM permission WHERE name = $1 LIMIT 1`
	err := tx.QueryRow(ctx, query, permissionName).Scan(&permissionId)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", fmt.Errorf("no permission found with name [%s]", permissionName)
		}
		return "", fmt.Errorf("failed to get permission with name [%s]: %w", permissionName, err)
	}
	s.permissionCache[permissionName] = permissionId
	return permissionId, nil
}
