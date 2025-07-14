package cmd

import (
	"context"
	"github.com/spf13/cobra"
	"github.com/tucowsinc/tdp-database-design/tools/tdp-tld-settings-migrator/internal/app/handler"
	"github.com/tucowsinc/tdp-database-design/tools/tdp-tld-settings-migrator/internal/app/service"
	"github.com/tucowsinc/tdp-database-design/tools/tdp-tld-settings-migrator/internal/pkg/prompt"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/logger/zap"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
	"log"
	"strings"
	"time"
)

var filePath string

var migrateCmd = &cobra.Command{
	Use:   "migrate-tld -f <file> [-s <host>] [-p <port>] [-d <dbname>] [-u <user>] [-w <password>]",
	Short: "migrate tld settings from a csv file to database",
	Long: `This command is used to migrate data from a csv file with tld settings provided via flag to database tld_config module.
Provided csv file should use ";" as a separator and should have the following columns: "Tenant Name", "TLD Name", "Category Name", "Setting Name", "Value to upload".
The "Value to upload" provided in the file should have valid <attr_value_type> for the specified <category_name> and <setting_name>, otherwise the migration will fail and no changes to database state will be made.
"Category Name" and "Setting Name" values should have an existing entry in v_attribute with the key in the format "tld.<category_name>.<setting_name>", otherwise the corresponding line from the file will be ignored.
`,
	Example: "migrate-tld -f example.csv",
	Run: func(cmd *cobra.Command, args []string) {
		var err error
		if strings.TrimSpace(dbConf.Username) == "" {
			dbConf.Username, err = prompt.Run("postgres user")
		}
		if err != nil {
			log.Fatal("failed to parse entered database user", logger.Fields{"error": err})
		}
		if strings.TrimSpace(dbConf.Password) == "" {
			dbConf.Password, err = prompt.Run("postgres password", prompt.HideEntered())
		}
		if err != nil {
			log.Fatal("failed to parse entered database password", logger.Fields{"error": err})
		}

		log := zap.NewTdpLogger(zap.LoggerConfig{
			Environment:  "development",
			OutputSink:   "stderr",
			LogLevel:     "debug",
			RedactValues: []string{dbConf.Username, dbConf.Password},
		})

		pgConf, err := dbConf.PostgresPoolConfig()
		if err != nil {
			log.Fatal("failed to get postgres pool config", logger.Fields{"error": err})
		}

		db, err := database.New(pgConf, log)
		if err != nil {
			log.Fatal("failed to create connection to Domains DB", logger.Fields{"error": err})
		}
		defer db.Close()

		s := service.New(db, log)
		h := handler.New(s)
		ctx, done := context.WithTimeout(cmd.Context(), time.Duration(dbConf.Timeout)*time.Second)
		defer done()
		err = h.MigrateTLDFromCSV(ctx, filePath)
		if err != nil {
			log.Error("migration failed - no changes to database made, please review and fix the value in file and repeat the command",
				logger.Fields{"file": filePath, "error": err})
		}
	},
}

func init() {
	migrateCmd.Flags().StringVarP(&dbConf.Username, "user", "u", "", "postgres user (DO NOT USE flag for PROD credentials, use prompt instead)")
	migrateCmd.Flags().StringVarP(&dbConf.Password, "pass", "w", "", "postgres password (DO NOT USE flag for PROD credentials, use prompt instead)")
	migrateCmd.Flags().StringVarP(&dbConf.HostName, "host", "s", "localhost", "postgres host")
	migrateCmd.Flags().IntVarP(&dbConf.Port, "port", "p", 5432, "postgres port")
	migrateCmd.Flags().StringVarP(&dbConf.DBName, "dbname", "d", "tdpdb", "postgres database name")
	migrateCmd.Flags().IntVarP(&dbConf.Timeout, "timeout", "t", 5, "postgres database connection timeout in seconds")

	migrateCmd.Flags().StringVarP(&filePath, "file", "f", "", "path to the csv file")

	if err := migrateCmd.MarkFlagRequired("file"); err != nil {
		log.Fatalf("failed to mark flag as required: %v", err)
	}

	rootCommand.AddCommand(migrateCmd)
}
