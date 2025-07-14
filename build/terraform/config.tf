terraform {
  required_version = ">=1.3"
  backend "s3" {}
}

provider "aws" {
  region = var.default_region
}
