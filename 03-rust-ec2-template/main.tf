# Rust Lambda dev box: launch template for Amazon Linux 2023 on Graviton (arm64).
# Standalone stack. Not related to 00-ssm and not part of the Lambda stack in ../infra.
# Runs in the DEFAULT VPC; instances get a public IP from the default (public) subnet.
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "rust-lambda-dev"
    }
  }
}

data "aws_vpc" "default" {
  default = true
}

# No inbound rules: connect with SSM Session Manager, not SSH. Outbound open for rustup, crates.io, PyPI, HashiCorp.
resource "aws_security_group" "rust_dev" {
  name_prefix = "rust-dev-"
  description = "Rust dev box: no inbound, all outbound"
  vpc_id      = data.aws_vpc.default.id

  tags = { Name = "rust-dev" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "all_out" {
  security_group_id = aws_security_group.rust_dev.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_launch_template" "rust_dev" {
  name        = var.name
  description = "Rust Lambda dev box (AL2023, arm64)"

  # Resolved at launch time: every new instance gets the latest AL2023 arm64 AMI
  image_id      = "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
  instance_type = var.instance_type

  # Existing instance profile (not created here)
  iam_instance_profile {
    name = var.instance_profile_name
  }

  vpc_security_group_ids = [aws_security_group.rust_dev.id]

  user_data = base64encode(file("${path.module}/install.sh"))

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
  }

  # The 8 GB AL2023 default is too small for Rust build artifacts
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.volume_size_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  update_default_version = true

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = var.name }
  }

  tag_specifications {
    resource_type = "volume"
    tags          = { Name = var.name }
  }
}

output "launch_template_name" {
  value = aws_launch_template.rust_dev.name
}

output "launch_command" {
  description = "Starts one instance in the default VPC (AWS picks a default subnet)"
  value       = "aws ec2 run-instances --region ${var.region} --launch-template LaunchTemplateName=${aws_launch_template.rust_dev.name},Version='$Latest' --count 1"
}
