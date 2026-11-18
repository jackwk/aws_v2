terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
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

data "aws_caller_identity" "current" {}

# Everything from parts 01-03 is discovered via SSM / deterministic names
data "aws_ssm_parameter" "kb_id" {
  name = "/${var.project_prefix}/${var.environment}/knowledge_base_id"
}

data "aws_ssm_parameter" "data_source_id" {
  name = "/${var.project_prefix}/${var.environment}/data_source_id"
}

locals {
  account_id      = data.aws_caller_identity.current.account_id
  ingest_function = var.ingest_lambda == "rust" ? "${var.project_prefix}-faers-rust-lambda-${var.environment}" : "${var.project_prefix}-ingest-faers-${var.environment}"
  glue_job        = "${var.project_prefix}-faers-processing-${var.environment}"
  kb_id           = data.aws_ssm_parameter.kb_id.value
  data_source_id  = data.aws_ssm_parameter.data_source_id.value
}
