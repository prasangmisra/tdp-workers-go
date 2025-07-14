variables {
  image_tag  = "set-me"
  namespace  = "set-me"
  datacenter = "set-me"
  image_name                   = "ghcr.io/tucowsinc/tdp/worker"
  domain_host_workers_count    = "1"
  domain_contact_workers_count = "1"
  domain_domain_workers_count  = "1"
  domain_hosting_workers_count = "1"
  poll_workers_count    = "1"
}

job "domain-workers" {
  datacenters = ["${var.datacenter}"]
  namespace   = "${var.namespace}"
  type        = "service"

  meta {
    run_uuid = "${uuidv4()}"
  }

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  constraint {
    attribute = "${meta.namespace}"
    operator  = "="
    value     = "${var.namespace}"
  }

  vault {
    policies  = ["read_all"]
    namespace = "${var.namespace}"
  }

  group "host-worker-instances" {
    count = "${var.domain_host_workers_count}"

    ephemeral_disk {
      size = 150
    }

    task "host-worker" {
      driver = "docker"

      template {
        data        = var.environment_vars
        env         = true
        destination = "/app/.env"
        change_mode = "restart"
        splay       = "45s"
      }

      config {
        image              = "${var.image_name}-host:${var.image_tag}"
        image_pull_timeout = "10m"
        force_pull         = true

        labels {
          com_docker_job_type     = "app"
          com_docker_namespace    = "${NOMAD_NAMESPACE}"
          com_docker_job          = "${NOMAD_JOB_NAME}"
          com_docker_service_name = "${NOMAD_GROUP_NAME}"
          com_docker_task_name    = "${NOMAD_TASK_NAME}"
          com_docker_alloc        = "${NOMAD_ALLOC_ID}"
        }

        logging {
          type = "json-file"
          config {
            max-size  = "10m"
            env       = "CONFIG_LOCAL_SUFFIX,SERVICE_NAME"
            env-regex = "NOMAD_.*"
          }
        }
      }

      env {
        BUILD_ENV      = "dev"
        DOCKER_STAGE   = "dev"
        SERVICE_NAME   = "host-worker"
        RABBITMQ_QUEUE = "WorkerJobHostProvision"
      }

      service {
        name = "host-worker"
        tags = ["host-worker"]
      }

      resources {
        cpu    = 100 # 100mhz
        memory = 50  # 50mb
      }
    }

    task "host-updater" {
      driver = "docker"

      template {
        data        = var.environment_vars
        env         = true
        destination = "/app/.env"
        change_mode = "restart"
        splay       = "45s"
      }

      config {
        image              = "${var.image_name}-host-updater:${var.image_tag}"
        image_pull_timeout = "10m"
        force_pull         = true

        labels {
          com_docker_job_type     = "app"
          com_docker_namespace    = "${NOMAD_NAMESPACE}"
          com_docker_job          = "${NOMAD_JOB_NAME}"
          com_docker_service_name = "${NOMAD_GROUP_NAME}"
          com_docker_task_name    = "${NOMAD_TASK_NAME}"
          com_docker_alloc        = "${NOMAD_ALLOC_ID}"
        }

        logging {
          type = "json-file"
          config {
            max-size  = "10m"
            env       = "CONFIG_LOCAL_SUFFIX,SERVICE_NAME"
            env-regex = "NOMAD_.*"
          }
        }
      }

      env {
        BUILD_ENV      = "dev"
        DOCKER_STAGE   = "dev"
        SERVICE_NAME   = "host-updater"
        RABBITMQ_QUEUE = "WorkerJobHostProvisionUpdate"
      }

      service {
        name = "host-updater"
        tags = ["host-updater"]
      }

      resources {
        cpu    = 100 # 100mhz
        memory = 50  # 50mb
      }
    }


  }

  group "contact-worker-instances" {
    count = "${var.domain_contact_workers_count}"

    ephemeral_disk {
      size = 150
    }

    task "contact-worker" {
      driver = "docker"

      template {
        data        = var.environment_vars
        env         = true
        destination = "/app/.env"
        change_mode = "restart"
        splay       = "45s"
      }

      config {
        image              = "${var.image_name}-contact:${var.image_tag}"
        image_pull_timeout = "10m"
        force_pull         = true

        labels {
          com_docker_job_type     = "app"
          com_docker_namespace    = "${NOMAD_NAMESPACE}"
          com_docker_job          = "${NOMAD_JOB_NAME}"
          com_docker_service_name = "${NOMAD_GROUP_NAME}"
          com_docker_task_name    = "${NOMAD_TASK_NAME}"
          com_docker_alloc        = "${NOMAD_ALLOC_ID}"
        }

        logging {
          type = "json-file"
          config {
            max-size  = "10m"
            env       = "CONFIG_LOCAL_SUFFIX,SERVICE_NAME"
            env-regex = "NOMAD_.*"
          }
        }
      }

      env {
        BUILD_ENV      = "dev"
        DOCKER_STAGE   = "dev"
        SERVICE_NAME   = "contact-worker"
        RABBITMQ_QUEUE = "WorkerJobContactProvision"
      }

      service {
        name = "contact-worker"
        tags = ["contact-worker"]
      }

      resources {
        cpu    = 100 # 100mhz
        memory = 50  # 50mb
      }
    }

    task "contact-updater" {
      driver = "docker"

      template {
        data        = var.environment_vars
        env         = true
        destination = "/app/.env"
        change_mode = "restart"
        splay       = "45s"
      }

      config {
        image              = "${var.image_name}-contact-updater:${var.image_tag}"
        image_pull_timeout = "10m"
        force_pull         = true

        labels {
          com_docker_job_type     = "app"
          com_docker_namespace    = "${NOMAD_NAMESPACE}"
          com_docker_job          = "${NOMAD_JOB_NAME}"
          com_docker_service_name = "${NOMAD_GROUP_NAME}"
          com_docker_task_name    = "${NOMAD_TASK_NAME}"
          com_docker_alloc        = "${NOMAD_ALLOC_ID}"
        }

        logging {
          type = "json-file"
          config {
            max-size  = "10m"
            env       = "CONFIG_LOCAL_SUFFIX,SERVICE_NAME"
            env-regex = "NOMAD_.*"
          }
        }
      }

      env {
        BUILD_ENV      = "dev"
        DOCKER_STAGE   = "dev"
        SERVICE_NAME   = "contact-updater"
        RABBITMQ_QUEUE = "WorkerJobContactProvisionUpdate"
      }

      service {
        name = "contact-updater"
        tags = ["contact-updater"]
      }

      resources {
        cpu    = 100 # 100mhz
        memory = 50  # 50mb
      }
    }


  }

  group "domain-worker-instances" {
    count = "${var.domain_domain_workers_count}"

    ephemeral_disk {
      size = 150
    }

    task "domain-worker" {
      driver = "docker"

      template {
        data        = var.environment_vars
        env         = true
        destination = "/app/.env"
        change_mode = "restart"
        splay       = "45s"
      }

      config {
        image              = "${var.image_name}-domain:${var.image_tag}"
        image_pull_timeout = "10m"
        force_pull         = true

        labels {
          com_docker_job_type     = "app"
          com_docker_namespace    = "${NOMAD_NAMESPACE}"
          com_docker_job          = "${NOMAD_JOB_NAME}"
          com_docker_service_name = "${NOMAD_GROUP_NAME}"
          com_docker_task_name    = "${NOMAD_TASK_NAME}"
          com_docker_alloc        = "${NOMAD_ALLOC_ID}"
        }

        logging {
          type = "json-file"
          config {
            max-size  = "10m"
            env       = "CONFIG_LOCAL_SUFFIX,SERVICE_NAME"
            env-regex = "NOMAD_.*"
          }
        }
      }

      env {
        BUILD_ENV      = "dev"
        DOCKER_STAGE   = "dev"
        SERVICE_NAME   = "domain-worker"
        RABBITMQ_QUEUE = "WorkerJobDomainProvision"
      }

      service {
        name = "domain-worker"
        tags = ["domain-worker"]
      }

      resources {
        cpu    = 100 # 100mhz
        memory = 50  # 50mb
      }
    }

    task "domain-updater" {
      driver = "docker"

      template {
        data        = var.environment_vars
        env         = true
        destination = "/app/.env"
        change_mode = "restart"
        splay       = "45s"
      }

      config {
        image              = "${var.image_name}-domain-updater:${var.image_tag}"
        image_pull_timeout = "10m"
        force_pull         = true

        labels {
          com_docker_job_type     = "app"
          com_docker_namespace    = "${NOMAD_NAMESPACE}"
          com_docker_job          = "${NOMAD_JOB_NAME}"
          com_docker_service_name = "${NOMAD_GROUP_NAME}"
          com_docker_task_name    = "${NOMAD_TASK_NAME}"
          com_docker_alloc        = "${NOMAD_ALLOC_ID}"
        }

        logging {
          type = "json-file"
          config {
            max-size  = "10m"
            env       = "CONFIG_LOCAL_SUFFIX,SERVICE_NAME"
            env-regex = "NOMAD_.*"
          }
        }
      }

      env {
        BUILD_ENV      = "dev"
        DOCKER_STAGE   = "dev"
        SERVICE_NAME   = "domain-updater"
        RABBITMQ_QUEUE = "WorkerJobDomainProvisionUpdate"
      }

      service {
        name = "domain-updater"
        tags = ["domain-updater"]
      }

      resources {
        cpu    = 100 # 100mhz
        memory = 50  # 50mb
      }
    }


  }

  group "poll-worker-instances" {
    count = "${var.poll_workers_count}"

    ephemeral_disk {
      size = 150
    }

    task "poll-worker" {
      driver = "docker"

      template {
        data        = <<EOH
                    RABBITMQ_HOSTNAME={{ key "rabbitmq/amqp-host" }}
                    RABBITMQ_PORT={{ key "rabbitmq/amqp-port" }}
                    RABBITMQ_USERNAME={{ with secret "kv/rabbitmq" }}{{ .Data.data.username }}{{ end }}
                    RABBITMQ_PASSWORD={{ with secret "kv/rabbitmq" }}{{ .Data.data.password }}{{ end }}
                    RABBITMQ_EXCHANGE=test
                    DBHOST="{{ key "database/host" }}"
                    DBPORT="{{ keyOrDefault "database/port" "5432" }}"
                    DBUSER="{{ with secret "kv/db" }}{{ .Data.data.username }}{{ end }}"
                    DBNAME="{{ keyOrDefault "database/name" "tdpdb" }}"
                    DBPASS="{{ with secret "kv/db" }}{{ .Data.data.password }}{{ end }}"
                    LOG_LEVEL=debug 
                EOH
        env         = true
        destination = "/app/.env"
        change_mode = "restart"
        splay       = "45s"
      }

      config {
        image              = "${var.image_name}-poll-worker:${var.image_tag}"
        image_pull_timeout = "10m"
        force_pull         = true

        labels {
          com_docker_job_type     = "app"
          com_docker_namespace    = "${NOMAD_NAMESPACE}"
          com_docker_job          = "${NOMAD_JOB_NAME}"
          com_docker_service_name = "${NOMAD_GROUP_NAME}"
          com_docker_task_name    = "${NOMAD_TASK_NAME}"
          com_docker_alloc        = "${NOMAD_ALLOC_ID}"
        }

        logging {
          type = "json-file"
          config {
            max-size  = "10m"
            env       = "CONFIG_LOCAL_SUFFIX,SERVICE_NAME"
            env-regex = "NOMAD_*"
          }
        }
      }

      env {
        BUILD_ENV      = "dev"
        DOCKER_STAGE   = "dev"
        SERVICE_NAME   = "poll-worker"
        RABBITMQ_QUEUE = "WorkerPollMessages"
        NOTIFICATION_QUEUE = "WorkerNotifications"
      }

      service {
        name = "poll-worker"
        tags = ["poll-worker"]
      }

      resources {
        cpu    = 250 # 250mhz
        memory = 100 # 500mb
      }
    }
  }
}

variable environment_vars {
  default = <<EOH
RABBITMQ_HOSTNAME={{ key "rabbitmq/amqp-host" }}
RABBITMQ_PORT={{ key "rabbitmq/amqp-port" }}
RABBITMQ_USERNAME={{ with secret "kv/rabbitmq" }}{{ .Data.data.username }}{{ end }}
RABBITMQ_PASSWORD={{ with secret "kv/rabbitmq" }}{{ .Data.data.password }}{{ end }}    
RABBITMQ_EXCHANGE=test
DD_TRACE_ENABLED={{ keyOrDefault "services/domain-workers/datadog/dd_trace_enabled" "False" }}
INSECURE={{ keyOrDefault "services/domain-workers/opentelemetry/insecure" "False" }}
NOOP_TRACER_ENABLED={{ keyOrDefault "services/domain-workers/opentelemetry/noop_tracer_enabled" "True" }}
OTEL_ENDPOINT={{ key "services/domain-workers/opentelemetry/otel_endpoint"}}
DBHOST="{{ key "database/host" }}"
DBPORT="{{ keyOrDefault "database/port" "5432" }}"
DBUSER="{{ with secret "kv/db" }}{{ .Data.data.username }}{{ end }}"
DBNAME="{{ keyOrDefault "database/name" "tdpdb" }}"
DBPASS="{{ with secret "kv/db" }}{{ .Data.data.password }}{{ end }}"
LOG_LEVEL=debug 
    EOH
}
