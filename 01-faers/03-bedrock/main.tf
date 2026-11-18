terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # s3vectors + AgentCore resources need 6.x
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_ssm_parameter" "processed_bucket" {
  name = "/${var.project_prefix}/${var.environment}/processed_bucket"
}

data "aws_caller_identity" "current" {}

locals {
  account_id       = data.aws_caller_identity.current.account_id
  processed_bucket = data.aws_ssm_parameter.processed_bucket.value
  embedding_model  = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"
}
