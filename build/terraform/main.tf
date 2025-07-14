locals {
  db_environment = [
    {
      "name" : "DBHOST",
      "value" : data.aws_rds_cluster.aurora-cluster.endpoint
    },
    {
      "name" : "DBUSER",
      "value" : "tucows"
    },
    {
      "name" : "DBPORT",
      "value" : "5432"
    },
    {
      "name" : "DBNAME",
      "value" : "tdpdb"
    }
  ]
  db_secrets = [
    {
      "name" : "DBPASS",
      "valueFrom" : data.aws_secretsmanager_secret.db-user-tucows.arn
    },
  ]
  rabbit_environment = [
    {
      "name" : "RABBITMQ_HOSTNAME",
      "value" : replace(data.aws_mq_broker.tdp-rmq-broker.instances[0].console_url, "https://", "")
    },
    {
      "name" : "RABBITMQ_PORT",
      "value" : "5671"
    },
    {
      "name" : "RABBITMQ_USERNAME",
      "value" : "mqadmin"
    },
    {
      "name" : "RABBITMQ_TLS_ENABLED",
      "value" : "true"
    },
    {
      "name" : "RABBITMQ_TLS_SKIP_VERIFY",
      "value" : "true"
    },
    {
      "name" : "RABBITMQ_EXCHANGE",
      "value" : "test"
    },
  ]
  rabbit_secrets = [
    {
      "name" : "RABBITMQ_PASSWORD",
      "valueFrom" : data.aws_secretsmanager_secret.mq-user-mqadmin.arn
    },
  ]
  hosting_environment = [
    {
      "name" : "AWS_SQS_QUEUE_NAME",
      "value" : "final-state-order.fifo"
    },
    {
      "name" : "AWS_SQS_QUEUE_ACCOUNT_ID",
      "value" : "${var.hosting_project_account_id}"
    },
    {
      "name" : "AWS_ROLES",
      "value" : "[{\"arn\":\"arn:aws:iam::${var.hosting_project_account_id}:role/tdp-to-sqs-role\", \"session_name\":\"hosting-role\"}]"
    }
  ]
  hosting_secrets = [
    {
      "name" : "AWS_HOSTING_API_KEY",
      "valueFrom" : "${data.aws_secretsmanager_secret.hosting-credentials.arn}:AWS_HOSTING_API_KEY::"
    },
    {
      "name" : "AWS_HOSTING_API_BASE_ENDPOINT",
      "valueFrom" : "${data.aws_secretsmanager_secret.hosting-credentials.arn}:AWS_HOSTING_API_BASE_ENDPOINT::"
    },
  ]
  account_id = data.aws_caller_identity.current_account.account_id
}

module "ecs_service_workers" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "5.0.1"

  for_each    = { for k, v in var.workers : k => v }
  name        = each.key
  cluster_arn = data.aws_ecs_cluster.tdp-ecs.arn
  cpu         = 256
  memory      = 512
  container_definitions = {
    "${each.key}" = {
      cpu       = 256
      memory    = 512
      essential = true
      image     = "${local.account_id}.dkr.ecr.${var.default_region}.amazonaws.com/${each.key}:${each.value.label}"
      secrets = concat(
        each.value.need_db ? local.db_secrets : [],
        each.value.need_mq ? local.rabbit_secrets : [],
        each.value.need_hosting ? local.hosting_secrets : [],
      [])
      environment = concat(
        each.value.need_db ? local.db_environment : [],
        each.value.need_mq ? local.rabbit_environment : [],
        each.value.need_hosting ? local.hosting_environment : [],
        [
          {
            "name" : "RABBITMQ_QUEUE",
            "value" : each.value.queuename
          },
          {
            "name" : "LOG_LEVEL",
            "value" : "INFO"
          }
        ]
      )
    }
  }

  subnet_ids           = data.aws_subnets.subnets.ids
  security_group_rules = var.ecs_security_group_rules
  tags                 = var.tags
}


module "ecs_service_hostings" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "5.0.1"

  for_each    = { for k, v in var.hostings : k => v }
  name        = each.key
  cluster_arn = data.aws_ecs_cluster.tdp-ecs.arn
  cpu         = 256
  memory      = 512
  tasks_iam_role_statements = [
    {
      actions   = ["sts:AssumeRole"]
      effect    = "Allow"
      resources = ["arn:aws:iam::${var.hosting_project_account_id}:role/tdp-to-sqs-role"]
      sid       = "SQSCrossAccount"
    }
  ]
  container_definitions = {
    "${each.key}" = {
      cpu       = 256
      memory    = 512
      essential = true
      image     = "${local.account_id}.dkr.ecr.${var.default_region}.amazonaws.com/${each.key}:${each.value.label}"
      secrets = concat(
        each.value.need_db ? local.db_secrets : [],
        each.value.need_mq ? local.rabbit_secrets : [],
        each.value.need_hosting ? local.hosting_secrets : [],
      [])
      environment = concat(
        each.value.need_db ? local.db_environment : [],
        each.value.need_mq ? local.rabbit_environment : [],
        each.value.need_hosting ? local.hosting_environment : [],
        [
          {
            "name" : "RABBITMQ_QUEUE",
            "value" : each.value.queuename
          },
          {
            "name" : "LOG_LEVEL",
            "value" : "INFO"
          }
        ]
      )
    }
  }

  subnet_ids           = data.aws_subnets.subnets.ids
  security_group_rules = var.ecs_security_group_rules
  tags                 = var.tags
}

