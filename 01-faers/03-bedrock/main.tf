provider "aws" {
  region = var.aws_region
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_ssm_parameter" "processed_bucket" {
  name = "/${var.project_prefix}/${var.environment}/processed_bucket"
}

data "aws_caller_identity" "current" {}
