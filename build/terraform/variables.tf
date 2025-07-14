variable "default_region" {
  default = ""
}

variable "workers" {
  description = "map describing Workers and their specific parameters"
  type        = map(any)
  default = {
    "worker-job-scheduler" = {
      queuename    = ""
      label        = "latest"
      need_db      = "true"
      need_mq      = "true"
      need_hosting = "false"
    }
    #, "worker-host" = {
    #   queuename     = "WorkerJobHostProvision"
    #   label         = "latest"
    # },
    # "worker-host-updater" = {
    #   queuename     = "WorkerJobHostProvisionUpdate"
    #   label         = "latest"
    # },
    # "worker-contact" = {
    #   queuename     = "WorkerJobContactProvision"
    #   label         = "latest"
    # },
    # "worker-contact-updater" = {
    #   queuename     = "WorkerJobContactProvisionUpdate"
    #   label         = "latest"
    # },
    # "worker-domain" = {
    #   queuename     = "WorkerJobDomainProvision"
    #   label         = "latest"
    # },
    # "worker-domain-updater" = {
    #   queuename     = "WorkerJobDomainProvisionUpdate"
    #   label         = "latest"
    # }
  }
}

variable "hostings" {
  description = "map describing hosting services and their specific parameters"
  type        = map(any)
  default = {
    "worker-hosting" = {
      queuename    = "WorkerJobHostingProvision"
      label        = "latest"
      need_db      = "true"
      need_mq      = "true"
      need_hosting = "true"
    },
    "worker-hosting-updater" = {
      queuename    = "WorkerJobHostingProvisionUpdate"
      label        = "latest"
      need_db      = "true"
      need_mq      = "true"
      need_hosting = "true"
    }
  }
}

variable "hosting_project_account_id" {
  default = ""
}

variable "ecs_security_group_rules" {
  default = {
    ingress_all = {
      type        = "ingress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
    egress_all = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default = {
    Owner       = "tucows"
    environment = "tdp-stg"
  }
}

variable "aurora_cluster_name" {
  default = ""
}