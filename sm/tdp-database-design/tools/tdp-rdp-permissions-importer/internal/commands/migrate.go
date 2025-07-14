package commands

import (
	"context"
	"log"
	"strings"
	"time"

	"github.com/tucowsinc/tdp-database-design/tools/tdp-rdp-permissions-importer/internal/handler"
	"github.com/tucowsinc/tdp-database-design/tools/tdp-rdp-permissions-importer/internal/prompt"
	"github.com/tucowsinc/tdp-database-design/tools/tdp-rdp-permissions-importer/internal/service"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/spf13/cobra"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/logger/zap"
)

var filePath string
var tld string

var migrateCommand = &cobra.Command{
	Use:     "migrate -f <file> -x <tld> [-s <host>] [-p <port>] [-d <dbname>] [-u <user>] [-w <password>]",
	Short:   "migrate RDP permissions from the provided csv file into TDP database",
	Example: "migrate -f filename.csv",
	Run: func(cmd *cobra.Command, args []string) {
		var err error
		if strings.TrimSpace(dbConf.Username) == "" {
			dbConf.Username, err = prompt.Run("postgres user")
		}
		if err != nil {
			log.Fatalf("failed to parse entered database user: %v", err)
		}
		if strings.TrimSpace(dbConf.Password) == "" {
			dbConf.Password, err = prompt.Run("postgres password", prompt.HideEntered())
		}
		if err != nil {
			log.Fatalf("failed to parse entered database password: %v", err)
		}

		db, err := pgxpool.New(cmd.Context(), dbConf.DatabaseConnectionString())
		if err != nil {
			log.Fatalf("failed to connect to the database: %v", err)
		}
		log.Println("connected to the database")
		defer db.Close()
		log := zap.NewTdpLogger(zap.LoggerConfig{
			Environment:  "development",
			OutputSink:   "stderr",
			LogLevel:     "debug",
			RedactValues: []string{dbConf.Username, dbConf.Password},
		})
		s := service.New(db, log)
		h := handler.New(s)
		ctx, done := context.WithTimeout(cmd.Context(), time.Duration(dbConf.Timeout)*time.Second)
		defer done()

		log.Printf("Tld: %s", tld)
		err = h.MigrateRDPPermissions(ctx, filePath, tld)
		if err != nil {
			log.Error("migration failed - no changes to database made, please review and fix the value in file and repeat the command", logger.Fields{
				"file":  filePath,
				"error": err,
			})
		}
	},
}

func init() {
	migrateCommand.Flags().StringVarP(&dbConf.Username, "user", "u", "", "postgres user (DO NOT USE flag for PROD credentials, use prompt instead)")
	migrateCommand.Flags().StringVarP(&dbConf.Password, "pass", "w", "", "postgres password (DO NOT USE flag for PROD credentials, use prompt instead)")
	migrateCommand.Flags().StringVarP(&dbConf.HostName, "host", "s", "localhost", "postgres host")
	migrateCommand.Flags().IntVarP(&dbConf.Port, "port", "p", 5432, "postgres port")
	migrateCommand.Flags().StringVarP(&dbConf.DBName, "dbname", "d", "tdpdb", "postgres database name")
	migrateCommand.Flags().IntVarP(&dbConf.Timeout, "timeout", "t", 5, "postgres database connection timeout in seconds")
	migrateCommand.Flags().StringVarP(&filePath, "file", "f", "", "path to the csv file")
	migrateCommand.Flags().StringVarP(&tld, "tld", "x", "", "tld to be used in the migration")

	if err := migrateCommand.MarkFlagRequired("file"); err != nil {
		log.Fatalf("failed to mark flag as required: %v", err)
	}

	if err := migrateCommand.MarkFlagRequired("tld"); err != nil {
		log.Fatalf("failed to mark flag as required: %v", err)
	}

	rootCommand.AddCommand(migrateCommand)
}
