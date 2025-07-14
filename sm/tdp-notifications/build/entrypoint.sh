#!/bin/bash
set -e


echo "Starting Daemon"
CompileDaemon --build="go build -o /main cmd/main.go" --command=/main