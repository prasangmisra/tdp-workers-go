#!/bin/bash

echo "Starting Daemon"
CompileDaemon --build="go build -o /main ${SERVICE_TYPE}/cmd/main.go" --command=/main
