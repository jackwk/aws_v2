terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "ssm-private-vpc"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Latest Amazon Linux 2023 AMI, resolved via the public SSM parameter
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---------------------------------------------------------------- IAM
resource "aws_iam_role" "ec2_ssm" {
  name_prefix = "ec2-ssm-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name_prefix = "ec2-ssm-"
  role        = aws_iam_role.ec2_ssm.name
}

# ---------------------------------------------------------------- Network
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true # required for private DNS on interface endpoints

  tags = { Name = "ssm-vpc" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = { Name = "ssm-private" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "ssm-private" }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ---------------------------------------------------------------- Security groups
resource "aws_security_group" "instance" {
  name_prefix = "ssm-instance-"
  description = "SSM-managed instance: no inbound, outbound HTTPS only"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "ssm-instance" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "endpoints" {
  name_prefix = "ssm-endpoints-"
  description = "Interface endpoints: HTTPS from the instance"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "ssm-endpoints" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  security_group_id            = aws_security_group.endpoints.id
  referenced_security_group_id = aws_security_group.instance.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_security_group_egress_rule" "instance_to_endpoints" {
  security_group_id            = aws_security_group.instance.id
  referenced_security_group_id = aws_security_group.endpoints.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

# S3 gateway endpoint: needed for package repos (dnf) and some SSM agent traffic
resource "aws_vpc_security_group_egress_rule" "instance_to_s3" {
  security_group_id = aws_security_group.instance.id
  prefix_list_id    = aws_vpc_endpoint.s3.prefix_list_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# ---------------------------------------------------------------- VPC endpoints
# Session Manager needs only ssm, ssmmessages and ec2messages (the "ec2" endpoint is not required).
locals {
  interface_endpoints = toset(["ssm", "ssmmessages", "ec2messages"])
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = { Name = "ssm-${each.key}" }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "ssm-s3" }
}

# ---------------------------------------------------------------- EC2
resource "aws_instance" "this" {
  ami                         = nonsensitive(data.aws_ssm_parameter.al2023.value)
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.private.id
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.instance.id]

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  tags = { Name = "ssm-managed-ec2" }

  # Don't replace the instance when a newer AMI is published
  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [aws_vpc_endpoint.interface]
}

# ---------------------------------------------------------------- Outputs
output "instance_id" {
  value = aws_instance.this.id
}

output "connect" {
  value = "aws ssm start-session --target ${aws_instance.this.id} --region ${var.region}"
}
