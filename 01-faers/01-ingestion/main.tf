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

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
