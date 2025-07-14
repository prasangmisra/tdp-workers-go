package commands

import "github.com/spf13/cobra"

var rootCommand = &cobra.Command{
	Use:   "rdp-migrator",
	Short: "A tool to migrate rdp permissions into tdp database",
	Long:  `A tool to migrate rdp permissions into tdp database`,
}

func ExecuteRoot() error {
	return rootCommand.Execute()
}
