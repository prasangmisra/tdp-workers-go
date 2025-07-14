![CICD](https://github.com/tucowsinc/tdp-workers-go/actions/workflows/build-and-deploy-job-scheduler.yml/badge.svg)

# Tucows Domain Platform Workers

This repo is a collection of various workers which are responsible for processing jobs. Jobs are created for the domain, contact, nameservers, etc by database and submitted to Message bus via the job scheduler.

## Prerequisites

- Connected to VPN
- Docker
- Make

## Getting Started

### Running Locally

1. Clone the repo:

   ```bash
   git clone git@github.com:tucowsinc/tdp-workers-go.git
   ```

2. Initialize Git Hooks:

   ```bash
   make init-git-hooks
   ```

3. Get AWS Hosting API Key:

   ```bash
   make getenv
   ```

4. Initialize the required submodules:

   ```bash
   make
   ```

5. **(Optional)** If you prefer to utilize the tdp-messagesbus-go and tdp-messages-go packages stored locally on your machine instead of the installed versions, please follow these steps:

   1. **Important:** Make sure that the `tdp-messagesbus-go` and `tdp-messages` repositories are located within the same parent directory as the `tdp-workers-go` repository. Plus, navigate to the `tdp-messages` directory and execute the `make compile-go-local` command to generate protobuf messages, creating the `tdp-messages-go` Go package.

   ```
     |--- Projects (parent directory)
       |- tdp-workers-go
       |- tdp-shared-go
       |- tdp-messagebus-go
       |- tdp-messages/tdp-messages-go (complied locally)
   ```

   2. Link go packages with the `tdp-workers-go` repository:

      ```bash
      # Link local tdp-messagebus-go package
      ln -s ../tdp-messagebus-go ./tdp-messagebus-go

      # Link local tdp-messages-go package
      ln -s ../tdp-messages/tdp-messages-go ./tdp-messages-go
      
      # Link local tdp-shared-go package
      ln -s ../tdp-shared-go ./tdp-shared-go
      ```

   3. Specify Docker Configuration:

      Modify the Docker configuration to include local package references in the go.mod file:

      ```bash
      export DOCKERFILE_PATH="tdp-workers-go/build/local.Dockerfile"

      export DOCKERFILE_CONTEXT="../.."
      ```

6. Start the workers:

   ```bash
   make up
   ```

7. Stop the workers:

   ```bash
   make down
   ```

### Running Tests

1. To run all tests:

   ```bash
   make all-tests
   ```

2. To run test for a specific worker:

   ```bash
   make {worker_name}-test
   ```

   e.g.

   ```bash
   make contact-test
   ```

3. To run individual test

   ```bash
   docker-compose -f build/docker-compose-workers.yml -p "${DC_PROJECT_NAME}" up -d --build domainsdb
   docker-compose -f build/docker-compose-workers.yml -p "${DC_PROJECT_NAME}" exec -w /db  -T domainsdb make all test-data

   # Change DBHOST in .env file to localhost

   go test ./poll_worker/... -v -cover -testify.m "TestPollMessageHandler"
   ```

## TDP Workers

The workers generate requests to the ry-interface for tasks such as creating domains, contacts, hosts, and hosting services. Subsequently, update workers are responsible for incorporating the responses from ry into the database. These tasks are coordinated by a job scheduler, which submits requests to the Message Bus.

Here are the TDP workers:

1. Domain.
2. Domain Updater.
3. Contact.
4. Contact Updater.
5. Host.
6. Host Updater.
7. Hosting.
8. Hosting Updater.
9. Job Scheduler.
10. Certificate Updater.
11. RY Poll Message Worker.
12. Poll Message Worker.
13. Poll Message Enqueuer.
14. Notification Worker.

## Code formatting

Code is formatted automatically by the git pre-commit hook.

- To format the code manually:

  ```bash
  make format-code
  ```

- To check the code formatting:

  ```bash
  make check-code-format
  ```

  <hr>

> Check [TDP-Dev](https://github.com/tucowsinc/tdp-dev-environment) for running integration tests.

# Environment Variables

This section provides a comprehensive list of environment variables used to configure the service.

## Docker Environment Variables:
| Environment Variable            | Mandatory | Default Value | Description                                                       |
|---------------------------------|:---------:|---------------|-------------------------------------------------------------------|
| `SERVICE_TYPE`                  |     ✅     | N/A           | Type of service being run                                         |

## Logging Environment Variables:
| Environment Variable            | Mandatory | Default Value | Description                                                       |
|---------------------------------|:---------:|---------------|-------------------------------------------------------------------|
| `LOG_LEVEL`                     |     ❌     | N/A           | Defines the logging level for the application (e.g., debug, info) |
| `LOG_ENVIRONMENT`               |     ❌     | N/A           | Defines the environment context for logging                       |
| `LOG_OUTPUT_SINK`               |     ❌     | N/A           | Specifies the destination for log output                          |

## RMQ Environment Variables:
| Environment Variable            | Mandatory | Default Value | Description                                                       |
|---------------------------------|:---------:|---------------|-------------------------------------------------------------------|
| `RABBITMQ_HOSTNAME`             |     ✅     | N/A           | RabbitMQ server hostname                                          |
| `RABBITMQ_PORT`                 |     ✅     | N/A           | RabbitMQ server port number                                       |
| `RABBITMQ_USERNAME`             |     ✅     | N/A           | RabbitMQ authentication username                                  |
| `RABBITMQ_PASSWORD`             |     ✅     | N/A           | RabbitMQ authentication password                                  |
| `RABBITMQ_EXCHANGE`             |     ✅     | N/A           | RabbitMQ exchange name                                            |
| `RABBITMQ_QUEUE`                |     ✅     | N/A           | RabbitMQ queue name                                               |
| `RABBITMQ_QUEUE_TYPE`           |     ✅     | N/A           | Specifies the type of RabbitMQ queue                              |
| `RABBITMQ_TLS_ENABLED`          |     ❌     | N/A           | Enables/disables TLS for RabbitMQ connection                      |
| `RABBITMQ_TLS_SKIP_VERIFY`      |     ❌     | N/A           | Enables/disables TLS certificate verification                     |
| `RABBITMQ_CERT_FILE`            |     ❌     | N/A           | Path to TLS certificate file                                      |
| `RABBITMQ_KEY_FILE`             |     ❌     | N/A           | Path to TLS key file                                              |
| `RABBITMQ_CA_FILE`              |     ❌     | N/A           | Path to TLS CA certificate file                                   |
| `RABBITMQ_VERIFY_SERVER_NAME`   |     ❌     | N/A           | Server name for TLS verification                                  |
| `MESSAGEBUS_READERS_COUNT`      |     ❌     | N/A           | Number of concurrent message bus readers                          |

## DB Environment Variables:
| Environment Variable            | Mandatory | Default Value | Description                                                       |
|---------------------------------|:---------:|---------------|-------------------------------------------------------------------|
| `DATABASE_URL`                  |     ✅     | N/A           | Complete database connection URL                                  |
| `DBPORT`                        |     ✅     | N/A           | Database port number                                              |
| `DBMAXCONN`                     |     ❌     | N/A           | Maximum number of database connections                            |
| `DBUSER`                        |     ✅     | N/A           | Database username                                                 |
| `DBPASS`                        |     ✅     | N/A           | Database password                                                 |
| `DBHOST`                        |     ✅     | N/A           | Database host address                                             |
| `DBNAME`                        |     ✅     | N/A           | Database name                                                     |
| `DBSSLMODE`                     |     ❌     | N/A           | SSL mode for database connection                                  |

## AWS Environment Variables:
| Environment Variable            | Mandatory | Default Value | Description                                                       |
|---------------------------------|:---------:|---------------|-------------------------------------------------------------------|
| `AWS_HOSTING_API_KEY`           |     ✅     | N/A           | AWS Hosting API authentication key                                |
| `AWS_HOSTING_API_BASE_ENDPOINT` |     ✅     | N/A           | Base endpoint URL for AWS Hosting API                             |
| `AWS_SSO_PROFILE_NAME`          |     ✅     | N/A           | AWS SSO profile name                                              |
| `AWS_SQS_QUEUE_NAME`            |     ✅     | N/A           | AWS SQS queue name                                                |
| `AWS_SQS_QUEUE_ACCOUNT_ID`      |     ✅     | N/A           | AWS account ID for SQS queue                                      |
| `AWS_ACCESS_KEY_ID`             |     ✅     | N/A           | AWS access key ID                                                 |
| `AWS_SECRET_ACCESS_KEY`         |     ✅     | N/A           | AWS secret access key                                             |
| `AWS_SESSION_TOKEN`             |     ✅     | N/A           | AWS session token                                                 |
| `AWS_REGION`                    |     ✅     | N/A           | AWS region                                                        |
| `AWS_ROLES`                     |     ✅     | N/A           | AWS roles configuration                                           |

## Tracing Environment Variables:
| Environment Variable            | Mandatory | Default Value | Description                                                       |
|---------------------------------|:---------:|---------------|-------------------------------------------------------------------|
| `DD_TRACE_ENABLED`              |     ❌     | N/A           | Enables/disables Datadog tracing                                  |


## Other Environment Variables:
| Environment Variable            | Mandatory | Default Value | Description                                                       |
|---------------------------------|:---------:|---------------|-------------------------------------------------------------------|
| `TESTING_MODE`                  |     ❌     | N/A           | Enables or disables testing mode                                  |


---

## Job Scheduler, Domain/Domain updater, Contact/Contact updater, Host/Host updater, and Notification workers:
| Environment Variable | Mandatory | Default Value | Description                                                                                 |
|----------------------|:---------:|---------------|---------------------------------------------------------------------------------------------|
| `Logging configs`    |     ❌     | N/A           | Logging configurations. See [Logging Environment Variables](#logging-environment-variables) |
| `RMQ configs`        |     ✅     | N/A           | RabbitMQ configurations. See [RMQ Environment Variables](#rmq-environment-variables)        |
| `DB configs`         |     ✅     | N/A           | Database configurations. See [DB Environment Variables](#db-environment-variables)          |
| `Tracing configs`    |     ❌     | N/A           | Tracing configurations. See [Tracing Environment Variables](#tracing-environment-variables) |

## Hosting worker:
| Environment Variable        | Mandatory | Default Value | Description                                                                                 |
|-----------------------------|:---------:|---------------|---------------------------------------------------------------------------------------------|
| `Logging configs`           |     ❌     | N/A           | Logging configurations. See [Logging Environment Variables](#logging-environment-variables) |
| `RMQ configs`               |     ✅     | N/A           | RabbitMQ configurations. See [RMQ Environment Variables](#rmq-environment-variables)        |
| `DB configs`                |     ✅     | N/A           | Database configurations. See [DB Environment Variables](#db-environment-variables)          |
| `Tracing configs`           |     ❌     | N/A           | Tracing configurations. See [Tracing Environment Variables](#tracing-environment-variables) |
| `AWS configs`               |     ✅     | N/A           | AWS configurations. See [AWS Environment Variables](#aws-environment-variables)             |
| `DNS_CHECK_TIMEOUT`         |     ❌     | N/A           | Timeout for DNS checks in seconds                                                           |
| `DNS_RESOLVER_ADDRESS`      |     ❌     | N/A           | DNS resolver address                                                                        |
| `DNS_RESOLVER_PORT`         |     ❌     | N/A           | DNS resolver port                                                                           |
| `DNS_RESOLVER_RECURSION`    |     ❌     | N/A           | Enable/disable DNS resolver recursion                                                       |
| `HOSTING_CNAME_DOMAIN`      |     ✅     | N/A           | Domain name for hosting CNAME records                                                       |
| `CERTBOT_API_BASE_ENDPOINT` |     ✅     | N/A           | Base endpoint for Certbot API                                                               |
| `CERT_BOT_TOKEN`            |     ✅     | N/A           | Authentication token for Certbot API                                                        |
| `CERT_BOT_API_TIMEOUT`      |     ❌     | N/A           | Timeout for Certbot API calls in seconds                                                    |
| `API_RETRY_COUNT`           |     ❌     | N/A           | Number of API retry attempts                                                                |
| `API_RETRY_MIN_WAIT_TIME`   |     ❌     | N/A           | Minimum wait time between retries in seconds                                                |
| `API_RETRY_MAX_WAIT_TIME`   |     ❌     | N/A           | Maximum wait time between retries in seconds                                                |

## Hosting Updater worker:
| Environment Variable        | Mandatory | Default Value | Description                                                                                 |
|-----------------------------|:---------:|---------------|---------------------------------------------------------------------------------------------|
| `Logging configs`           |     ❌     | N/A           | Logging configurations. See [Logging Environment Variables](#logging-environment-variables) |
| `DB configs`                |     ✅     | N/A           | Database configurations. See [DB Environment Variables](#db-environment-variables)          |
| `AWS configs`               |     ✅     | N/A           | AWS configurations. See [AWS Environment Variables](#aws-environment-variables)             |

## Poll Enqueuer, Certificate Updater workers:
| Environment Variable        | Mandatory | Default Value | Description                                                                                 |
|-----------------------------|:---------:|---------------|---------------------------------------------------------------------------------------------|
| `Logging configs`           |     ❌     | N/A           | Logging configurations. See [Logging Environment Variables](#logging-environment-variables) |
| `RMQ configs`               |     ✅     | N/A           | RabbitMQ configurations. See [RMQ Environment Variables](#rmq-environment-variables)        |
| `DB configs`                |     ✅     | N/A           | Database configurations. See [DB Environment Variables](#db-environment-variables)          |

## Poll Worker:
| Environment Variable | Mandatory | Default Value | Description                                                                                 |
|----------------------|:---------:|---------------|---------------------------------------------------------------------------------------------|
| `Logging configs`    |     ❌     | N/A           | Logging configurations. See [Logging Environment Variables](#logging-environment-variables) |
| `RMQ configs`        |     ✅     | N/A           | RabbitMQ configurations. See [RMQ Environment Variables](#rmq-environment-variables)        |
| `DB configs`         |     ✅     | N/A           | Database configurations. See [DB Environment Variables](#db-environment-variables)          |
| `NOTIFICATION_QUEUE` |     ❌     | N/A           | Name of the notification queue                                                              |


## Crons:
| Environment Variable | Mandatory | Default Value | Description                                                                                 |
|----------------------|:---------:|---------------|---------------------------------------------------------------------------------------------|
| `Logging configs`    |     ❌     | N/A           | Logging configurations. See [Logging Environment Variables](#logging-environment-variables) |
| `RMQ configs`        |     ✅     | N/A           | RabbitMQ configurations. See [RMQ Environment Variables](#rmq-environment-variables)        |
| `DB configs`         |     ✅     | N/A           | Database configurations. See [DB Environment Variables](#db-environment-variables)          |
| `CRON_TYPE`          |     ✅     | N/A           | Type of cron job configuration                                                              |


## Notes:
- ✅ indicates mandatory variables that must be set
- ❌ indicates optional variables
