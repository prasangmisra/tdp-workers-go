variables {
  image_tag       = "set-me"
  namespace       = "set-me"
  datacenter      = "set-me"
  container_count = "set-me"
}

job "job-scheduler" {
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

  group "job-scheduler-instances" {
    count = "${var.container_count}"

    ephemeral_disk {
      size = 150
    }

    task "job-scheduler" {
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
                    DD_TRACE_ENABLED={{ keyOrDefault "services/job-scheduler/datadog/dd_trace_enabled" "False" }}
                    INSECURE={{ keyOrDefault "services/job-scheduler/opentelemetry/insecure" "False" }}
                    NOOP_TRACER_ENABLED={{ keyOrDefault "services/job-scheduler/opentelemetry/noop_tracer_enabled" "True" }}
                    OTEL_ENDPOINT={{ key "services/job-scheduler/opentelemetry/otel_endpoint"}}
                    DBPASS="{{ with secret "kv/db" }}{{ .Data.data.password }}{{ end }}"
                    LOG_LEVEL=debug 
                EOH
        env         = true
        destination = "/app/.env"
        change_mode = "restart"
        splay       = "45s"
      }

      config {
        image              = "ghcr.io/tucowsinc/tdp/worker-job-scheduler:${var.image_tag}"
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
        BUILD_ENV                = "dev"
        DOCKER_STAGE             = "dev"
        SERVICE_NAME             = "job-scheduler"
        MESSAGEBUS_READERS_COUNT = 0
      }

      service {
        name = "job-scheduler"
        tags = ["job-scheduler"]
      }

      resources {
        cpu    = 250 # 250mhz
        memory = 100 # 500mb
      }
    }
  }
}
