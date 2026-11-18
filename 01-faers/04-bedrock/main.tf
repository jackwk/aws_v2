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

  default_tags {
    tags = {
      Project     = var.project_prefix
      Environment = var.environment
      Demo        = "true"
    }
  }
}

data "aws_ssm_parameter" "processed_bucket" {
  name = "/${var.project_prefix}/${var.environment}/processed_bucket"
}

data "aws_caller_identity" "current" {}

locals {
  account_id       = data.aws_caller_identity.current.account_id
  processed_bucket = data.aws_ssm_parameter.processed_bucket.value
  # "eu.amazon.nova-2-lite-v1:0" -> "amazon.nova-2-lite-v1:0"
  agent_foundation_model = replace(var.agent_model_id, "/^(eu|us|apac|global)\\./", "")
  embedding_model        = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"
}
