# TDP Notifications

This repository contains services of TDP Notifications system

## Table of Contents

- [Prerequisites](#prerequisites)
- [Local Setup](#local-setup)
- [GoLand Setup](#goland-setup)
- [VSCode Setup](#vscode-setup)
- [Accessing RabbitMQ Management Interface](#accessing-rabbitMQ-management-interface)
- [Accessing Database](#accessing-database)
- [Configuration Hierarchy](#configuration-hierarchy)
- [Swagger](#swagger)

## Prerequisites

Before setting up the project, ensure you have the following installed:

- [Go](https://golang.org/doc/install) (version 1.23.0 or later)
- [Docker](https://www.docker.com/get-started) (version 25.0 or later). [Docker Compose](https://docs.docker.com/compose/install/) (version 2) should be installed automatically with Docker
- [GoLand](https://www.jetbrains.com/go/) or [Visual Studio Code](https://code.visualstudio.com/) (optional, with Go extension)

In addition to that, in order to be able to regenerate mocks - you should have the [mockery](https://vektra.github.io/mockery/latest/installation/) tool installed.

## Getting Started

### Running Locally
1. Initialize the required submodules:

```bash
make git-init-sm
```

2. Initialize github hooks:

```bash
make git-init-hooks
```

3. Start all services:

```bash
make up
```

Or if you want to start a specific service, you can do it like this:

```bash
make up services=<service_name>
```

In order to run multiple specific services, run:

```bash
make up services="<service_name_1> <service_name_2>"
```

If you want to run services in a detach mode, you can do it like this:

```bash
make up services="-d <service_name_1> <service_name_2>"
```


#### Accessing Database

To access the databases (domainsdb and subdb) that we exposed in the Docker setup, here are the details to connect using PostgreSQL:

##### Accessing the `domainsdb`
You can connect to `domainsdb` on your local machine using the following credentials:

- **Host**: `localhost`
- **Port**: `5433`
- **Database**: `tdpdb`
- **Username**: `tucows`
- **Password**: `tucows1234`

##### Example: Accessing via `psql` from Command Line

To connect to the `domainsdb` using `psql`:

```bash
psql -h localhost -p 5433 -U tucows -d tdpdb
```

##### Accessing the `subdb`
You can connect to `subdb` on your local machine using the following credentials:

- **Host**: `localhost`
- **Port**: `5434`
- **Database**: `subtdpdb`
- **Username**: `tucows`
- **Password**: `tucows1234`

##### Example: Accessing via `psql` from Command Line

To connect to the `subdb` using `psql`:

```bash
psql -h localhost -p 5434 -U tucows -d subtdpdb
```

## Local Setup

### 1. Clone the Repository

```bash
git clone https://github.com/tucowsinc/tdp-notifications
cd tdp-notifications
```

### 2. Install Dependencies

```bash
go mod tidy
```

If you encounter a problem complaining about a `checksum mismatch`, you will need to do a few things:

Firstly set your environment variables 
- GOPROXY
- GOPRIVATE
- GONOSUMDB

as outlined here: https://github.com/tucowsinc/tdp-messages?tab=readme-ov-file#package-installation-2

Once you have done that, run

```bash
rm go.sum
go clean -modcache
go mod tidy
```


### 3. Start RabbitMQ

```bash
make up services="-d rabbitmq"
```

### 4. Set up env values

```bash
export RMQ_HOSTNAME="localhost"
export RMQ_PORT="5672"
export TLS_ENABLED="false"
export TLS_SKIP_VERIFY="false"
export LOG_OUTPUTSINK="stderr"
```

### 5. Run the service locally

```bash
go run api-service/cmd/main.go
```

### 6. Stopping RabbitMQ
After you are done, stop RabbitMQ

```bash
make down
```

## GoLand Setup

### 1. Configure the project in GoLand
Open the project in GoLand.

Go to Run > Edit Configurations and add a new Go Application configuration.

Set the following values:

```Name: Run Locally
Working directory: `$PROJECT_DIR$`
Package path: `github.com/tucowsinc/tdp-notifications/api-service/cmd`
File: $PROJECT_DIR$/api-service/cmd/main.go
Before launch: Add two steps in the following order:
Down: This will stop any previous services.
RMQ Up: This will start RabbitMQ.
To create the Down and RMQ Up configurations:

Down Configuration:
Add a new Makefile Target configuration.
Set the target to down and the working directory to $PROJECT_DIR$.
RMQ Up Configuration:
Add a new Makefile Target configuration.
Set the target to rmq-up and the working directory to $PROJECT_DIR$.
Run Run Locally to start RabbitMQ and the API service.
```

### 2. Stopping Services

To stop all services after testing, run the Down configuration or use the terminal:

```
make down
```

## VSCode Setup

### 1. Configuration

To debug the application locally using VSCode:

Open the project in VSCode.
Ensure the Go extension is installed.
Open the .vscode/launch.json file and add the following configuration:

```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Debug API Service locally",
            "type": "go",
            "request": "launch",
            "mode": "auto",
            "program": "${workspaceFolder}/api-service/cmd",
            "cwd": "${workspaceFolder}",
            "preLaunchTask": "Run RabbitMQ"
        }
    ]
}
```

### 2. Task Configuration

Add the following to `.vscode/tasks.json` to run RabbitMQ before debugging:

```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Run RabbitMQ",
            "type": "shell",
            "command": "make up services=\"-d rabbitmq\"",
            "problemMatcher": [],
            "group": {
                "kind": "build",
                "isDefault": true
            }
        }
    ]
}
```

### 3. Debugging

Press F5 to start debugging. VSCOde will automatically start RabbitMQ and then launch the service in debug mode

## Accessing RabbitMQ Management Interface

After RabbitMQ is running, you can access the management interface by navigating to:

```arduino
http://localhost:15672
```
Default credentials are:

Username: domains
Password: tucows


## Configuration Hierarchy
Local Development: Uses `localhost` for RabbitMQ, and TLS is typically disabled.
Docker Environment: Uses `rabbitmq-local` for RabbitMQ, with TLS enabled. These settings are automatically applied based on the environment detection in the Go configuration.

## Swagger
When you run the application, go to 
```arduino
http://localhost:<port>/swagger/index.html
```
to play around with the APIs

## Architecture docs
[Architecture Documentation](docs/docs.md)
