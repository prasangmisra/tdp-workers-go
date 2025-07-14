package main

import (
	"log"

	"github.com/tucowsinc/tdp-database-design/tools/tdp-rdp-permissions-importer/internal/commands"
)

func main() {
	if err := commands.ExecuteRoot(); err != nil {
		log.Fatalf("error executing command: %v", err)
	}
}
