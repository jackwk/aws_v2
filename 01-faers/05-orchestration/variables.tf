variable "project_prefix" {
  description = "Prefix for project resources"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g., dev, test)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "eu-central-1"
}

variable "ingest_lambda" {
  description = "Which ingestion Lambda the pipeline calls: \"python\" (01-ingestion) or \"rust\" (02-lambda-rust, arm64)"
  type        = string
  default     = "python"
  validation {
    condition     = contains(["python", "rust"], var.ingest_lambda)
    error_message = "ingest_lambda must be \"python\" or \"rust\"."
  }
}
