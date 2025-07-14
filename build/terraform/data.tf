data "aws_subnets" "subnets" {
  filter {
    name   = "tag:Name"
    values = ["*-private-backend-*"] # only select one subnet when we install the mq in SINGLE_INSTANCE mode
  }
}

data "aws_mq_broker" "tdp-rmq-broker" {
  broker_name = "tdp-rmq-broker"
}

data "aws_ecs_cluster" "tdp-ecs" {
  cluster_name = "dev-tdp-ecs" ## needs to be not platform specific
}

data "aws_rds_cluster" "aurora-cluster" {
  cluster_identifier = var.aurora_cluster_name ## needs to be not platform specific
}

data "aws_secretsmanager_secret" "hosting-credentials" {
  name = "hosting-credentials"
}

data "aws_secretsmanager_secret" "mq-user-mqadmin" {
  name = "generated-password-for-mq-user-mqadmin"
}

data "aws_secretsmanager_secret" "db-user-tucows" {
  name = "generated-password-for-db-user-tucows"
}

data "aws_caller_identity" "current_account" {}

data "aws_region" "current_region" {}
