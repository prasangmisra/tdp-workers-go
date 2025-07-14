package handler

import (
	"context"
	"encoding/csv"
	"fmt"
	"github.com/gocarina/gocsv"
	modelcsv "github.com/tucowsinc/tdp-database-design/tools/tdp-tld-settings-migrator/internal/app/model/csv"
	"io"
	"os"
)

func (h *handler) MigrateTLDFromCSV(ctx context.Context, filePath string) error {
	file, err := os.Open(filePath)
	if err != nil {
		return fmt.Errorf("failed to open file: %w", err)
	}
	defer file.Close()
	gocsv.SetCSVReader(func(in io.Reader) gocsv.CSVReader {
		r := csv.NewReader(in)
		r.Comma = ';'
		return r // Allows use semicolon as delimiter
	})

	var records []*modelcsv.TLDRecordCSV
	if err = gocsv.UnmarshalFile(file, &records); err != nil {
		return fmt.Errorf("failed to unmarshal csv file: %w", err)
	}

	return h.s.MigrateTLD(ctx, records)
}
