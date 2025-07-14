package cmd

import (
	"github.com/spf13/cobra"
)

var rootCommand = &cobra.Command{
	Use:   "migrator",
	Short: "migrator is a tool to migrate data from csv file to database",
	Long:  "migrator is a tool to migrate data from csv file to database",
}

func Execute() error {
	return rootCommand.Execute()
}
