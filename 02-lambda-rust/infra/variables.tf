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