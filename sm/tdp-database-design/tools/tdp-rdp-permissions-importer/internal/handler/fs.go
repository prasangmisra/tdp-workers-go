package handler

import (
	"context"
	"encoding/csv"
	"fmt"
	"io"
	"os"

	"github.com/gocarina/gocsv"
	modelcsv "github.com/tucowsinc/tdp-database-design/tools/tdp-rdp-permissions-importer/internal/model/csv"
)

func (h *handler) MigrateRDPPermissions(ctx context.Context, filePath, tld string) error {
	file, err := os.Open(filePath)
	if err != nil {
		return fmt.Errorf("failed to open file %s: %w", filePath, err)
	}
	defer file.Close()
	gocsv.SetCSVReader(func(in io.Reader) gocsv.CSVReader {
		r := csv.NewReader(in)
		r.Comma = ','
		return r
	})

	var records []*modelcsv.RDPRecord
	if err := gocsv.Unmarshal(file, &records); err != nil {
		return fmt.Errorf("failed to unmarshal CSV: %w", err)
	}

	if len(records) == 0 {
		return fmt.Errorf("no records found in the file")
	}

	return h.s.MigrateRDPPermissions(ctx, records, tld)
}
