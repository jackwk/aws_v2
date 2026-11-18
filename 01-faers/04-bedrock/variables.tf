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

variable "agent_model_id" {
  description = "Bedrock model (or inference profile) ID used by the AgentCore harness"
  type        = string
  default     = "eu.amazon.nova-2-lite-v1:0" # Nova v1 Lite/Pro fail tool calls in the harness
}
