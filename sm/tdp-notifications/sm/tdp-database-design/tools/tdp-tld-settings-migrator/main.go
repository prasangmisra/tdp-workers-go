package main

import (
	"github.com/tucowsinc/tdp-database-design/tools/tdp-tld-settings-migrator/cmd"
	"log"
)

func main() {
	if err := cmd.Execute(); err != nil {
		log.Fatalf("error executing command: %v", err)
	}
}
