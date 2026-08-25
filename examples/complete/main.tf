# Self-contained example. It builds its own VPC and subnets rather than looking
# up existing ones, so there is nothing to discover, nothing to tag in advance,
# and no data sources for the mocked test suite to override.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.96.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
  }
}

variable "availability_zones" {
  description = "AZs to place the example subnets in. Two minimum: a DB subnet group spans at least two AZs"
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b"]
}

variable "vpc_cidr" {
  description = "CIDR for the example VPC. Stays inside 10.0.0.0/8 so the module's default ingress and egress rules cover it"
  type        = string
  default     = "10.0.0.0/16"
}

resource "random_id" "this" {
  byte_length = 3
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "terraform-aws-aurora-${random_id.this.hex}"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.this.id
  availability_zone = var.availability_zones[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)

  tags = {
    Name = "terraform-aws-aurora-${random_id.this.hex}-private-${count.index}"
    Type = "Private"
  }
}

# Stands in for whatever actually connects to the cluster. Its id does not exist
# until apply, which is the case the module's ingress rules have to tolerate.
resource "aws_security_group" "client" {
  name_prefix = "test-aurora-client-"
  description = "example client security group"
  vpc_id      = aws_vpc.this.id

  lifecycle {
    create_before_destroy = true
  }
}

module "this" {
  source                    = "../../"
  cluster_identifier_prefix = "terraform-aws-aurora-${random_id.this.hex}"
  cluster_instance_count    = 1
  private_subnet_ids        = aws_subnet.private[*].id
  protect                   = false
  source_security_group_ids = [aws_security_group.client.id]
  vpc_id                    = aws_vpc.this.id
}

output "endpoint" {
  description = "Writer endpoint of the example cluster"
  value       = module.this.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint of the example cluster"
  value       = module.this.reader_endpoint
}

output "password_ssm_name" {
  description = "SSM parameter holding the master password"
  value       = module.this.password_ssm_name
}

output "security_group_id" {
  description = "Security group attached to the example cluster"
  value       = module.this.security_group_id
}
