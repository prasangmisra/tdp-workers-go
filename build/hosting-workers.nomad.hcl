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

job "hosting-workers" {
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

  group "hosting-worker-instances" {
    count = "${var.domain_hosting_workers_count}"

    ephemeral_disk {
      size = 150
    }

    task "hosting-worker" {
      driver = "docker"

      template {
        data        = var.environmnent_vars
        env         = true
        destination = "/app/.env"
        change_mode = "restart"
        splay       = "45s"
      }

      template {
        data = <<EOH
          AWS_HOSTING_API_KEY={{ with secret "kv/workers/hosting" }}{{ .Data.data.aws_api_key }}{{ end }}
          AWS_HOSTING_API_BASE_ENDPOINT="{{ key "services/retrieval_manager/hosting/url" }}"
          CERT_BOT_TOKEN={{ with secret "kv/cert_api"}}{{ .Data.data.token }}{{ end }}
        EOH
        env = true
        destination = "secrets.env"
        change_mode = "restart"
        splay = "45s"
      }      

      config {
        image              = "${var.image_name}-hosting:${var.image_tag}"
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
        SERVICE_NAME   = "hosting-worker"
        RABBITMQ_QUEUE = "WorkerJobHostingProvision"
      }

      service {
        name = "hosting-worker"
        tags = ["hosting-worker"]
      }

      resources {
        cpu    = 100 # 100mhz
        memory = 50  # 50mb
      }
    }

    task "certificate-updater-worker" {
      driver = "docker"

      template {
        data        = var.environmnent_vars
        env         = true
        destination = "/app/.env"
        change_mode = "restart"
        splay       = "45s"
      }


      config {
        image              = "${var.image_name}-hosting:${var.image_tag}"
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
        SERVICE_NAME   = "certificate-updater-worker"
        RABBITMQ_QUEUE = "WorkerJobHostingCertificateProvisionUpdate"
      }

      service {
        name = "certificate-updater-worker"
        tags = ["certificate-updater-worker"]
      }

      resources {
        cpu    = 100 # 100mhz
        memory = 50  # 50mb
      }
    }

  }
}

variable environmnent_vars {
  default = <<EOH
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
HOSTING_CNAME_DOMAIN=dev.cert.tucows.net
CERTBOT_API_BASE_ENDPOINT=http://tdpdevcert001.dev-ops-dns.cnco.tucows.systems:8080/api/v1
    EOH
}
