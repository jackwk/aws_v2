variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "name" {
  description = "Name of the launch template and tag of the instances"
  type        = string
  default     = "rust-lambda-dev"
}

variable "instance_type" {
  description = "Graviton type, matches the arm64 Lambda"
  type        = string
  default     = "t4g.large"
}

variable "instance_profile_name" {
  description = "Existing IAM instance profile"
  type        = string
  default     = "ec2-tf-for-lambda"
}

variable "volume_size_gb" {
  type    = number
  default = 50
}
