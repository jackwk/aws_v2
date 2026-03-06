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

data "aws_ssm_parameter" "raw_bucket" {
  name = "/${var.project_prefix}/${var.environment}/raw_bucket"
}
