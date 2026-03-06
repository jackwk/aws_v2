// ---------------------------------------------------------------------------------------------------------------------
// Provider Configuration & Data Sources
// ---------------------------------------------------------------------------------------------------------------------
provider "aws" {
  region = "eu-central-1"
}

data "aws_availability_zones" "available" {
  // Get all available availability zones in the current region
}

data "aws_region" "current" {
  // Get details about the current AWS region
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"] // Canonical owner ID for Amazon AMIs

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// IAM Role for EC2 with SSM Permissions
// ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_role" "ec2_ssm_role" {
  name = "EC2-SSM-Role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "EC2-SSM-Role"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core_attachment" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm_instance_profile" {
  name = "EC2-SSM-Instance-Profile"
  role = aws_iam_role.ec2_ssm_role.name
}

// ---------------------------------------------------------------------------------------------------------------------
// VPC and Subnet Configuration
// ---------------------------------------------------------------------------------------------------------------------
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true // Required for private DNS for VPC endpoints

  tags = {
    Name = "Main-VPC-SSM"
  }
}

resource "aws_subnet" "private_subnet_az1" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0] // Use the first available AZ

  tags = {
    Name = "Private-Subnet-AZ1"
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Route Table for Private Subnet (for S3 Gateway Endpoint)
// ---------------------------------------------------------------------------------------------------------------------
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "Private-Route-Table"
  }
}

resource "aws_route_table_association" "private_subnet_association" {
  subnet_id      = aws_subnet.private_subnet_az1.id
  route_table_id = aws_route_table.private_route_table.id
}

// ---------------------------------------------------------------------------------------------------------------------
// Security Group for Interface VPC Endpoints
// ---------------------------------------------------------------------------------------------------------------------
resource "aws_security_group" "vpc_endpoint_sg" {
  name        = "vpc-endpoint-sg"
  description = "Allow HTTPS traffic for VPC Interface Endpoints from within the VPC"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main_vpc.cidr_block]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1" // All protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "VPC-Endpoint-SG"
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// VPC Endpoints for Systems Manager and S3
// ---------------------------------------------------------------------------------------------------------------------

// SSM Endpoint
resource "aws_vpc_endpoint" "ssm_endpoint" {
  vpc_id              = aws_vpc.main_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_subnet_az1.id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "SSM-VPCEndpoint"
  }
}

// SSMMessages Endpoint
resource "aws_vpc_endpoint" "ssmmessages_endpoint" {
  vpc_id              = aws_vpc.main_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_subnet_az1.id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "SSMMessages-VPCEndpoint"
  }
}

// EC2 Endpoint (required by SSM for some operations)
resource "aws_vpc_endpoint" "ec2_endpoint" {
  vpc_id              = aws_vpc.main_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_subnet_az1.id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "EC2-VPCEndpoint"
  }
}

// EC2Messages Endpoint (required for SSM Session Manager)
resource "aws_vpc_endpoint" "ec2messages_endpoint" {
  vpc_id              = aws_vpc.main_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_subnet_az1.id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "EC2Messages-VPCEndpoint"
  }
}

// S3 Gateway Endpoint (SSM agent uses S3 for updates, logs, etc.)
resource "aws_vpc_endpoint" "s3_gateway_endpoint" {
  vpc_id            = aws_vpc.main_vpc.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_route_table.id] // Associate with the private subnet's route table

  tags = {
    Name = "S3-Gateway-VPCEndpoint"
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// EC2 Instance Configuration
// ---------------------------------------------------------------------------------------------------------------------
data "aws_security_group" "default_sg" {
  // Get the default security group for the VPC
  vpc_id = aws_vpc.main_vpc.id
  name   = "default"
}

resource "aws_instance" "ssm_managed_ec2" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = "t3.micro" // You can change this as needed
  subnet_id                   = aws_subnet.private_subnet_az1.id
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm_instance_profile.name
  associate_public_ip_address = false // No public IP for private subnet instance
  vpc_security_group_ids      = [data.aws_security_group.default_sg.id] // Use the VPC's default security group

  tags = {
    Name = "SSM-Managed-EC2-Instance"
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------------------------------------------------
output "vpc_id" {
  description = "The ID of the created VPC."
  value       = aws_vpc.main_vpc.id
}

output "private_subnet_id" {
  description = "The ID of the private subnet."
  value       = aws_subnet.private_subnet_az1.id
}

output "ec2_instance_id" {
  description = "The ID of the EC2 instance."
  value       = aws_instance.ssm_managed_ec2.id
}

output "ec2_instance_private_ip" {
  description = "The private IP address of the EC2 instance."
  value       = aws_instance.ssm_managed_ec2.private_ip
}

output "iam_role_name" {
  description = "The name of the IAM role created for EC2 SSM access."
  value       = aws_iam_role.ec2_ssm_role.name
}

output "ssm_interface_endpoints_dns" {
  description = "DNS entries for the SSM interface endpoints."
  value = {
    ssm         = aws_vpc_endpoint.ssm_endpoint.dns_entry[0].dns_name
    ssmmessages = aws_vpc_endpoint.ssmmessages_endpoint.dns_entry[0].dns_name
    ec2         = aws_vpc_endpoint.ec2_endpoint.dns_entry[0].dns_name
    ec2messages = aws_vpc_endpoint.ec2messages_endpoint.dns_entry[0].dns_name
  }
}
