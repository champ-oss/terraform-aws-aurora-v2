# Runs examples/complete end to end against mocked providers. The example has no
# data sources any more, so there is nothing to override: this is the whole
# config, applied, with zero AWS calls.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

mock_provider "random" {}

run "complete" {
  command = apply

  module {
    source = "./examples/complete"
  }

  # A DB subnet group needs at least two AZs, so the example must build at least
  # two subnets and they must be in different AZs.
  assert {
    condition     = length(aws_subnet.private) >= 2
    error_message = "the example must create at least two subnets"
  }

  assert {
    condition     = length(distinct(aws_subnet.private[*].availability_zone)) == length(aws_subnet.private)
    error_message = "example subnets must each be in a distinct AZ"
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private : s.vpc_id == aws_vpc.this.id])
    error_message = "example subnets must belong to the example VPC"
  }

  # The client SG id is unknown until apply. This is the case that broke the
  # module's ingress rules when they were keyed by value instead of index.
  assert {
    condition     = aws_security_group.client.vpc_id == aws_vpc.this.id
    error_message = "the client security group must belong to the example VPC"
  }

  assert {
    condition     = module.this.endpoint != "" && module.this.reader_endpoint != ""
    error_message = "the example must produce cluster endpoints"
  }

  assert {
    condition     = module.this.security_group_id != ""
    error_message = "the example must produce a security group"
  }

  assert {
    condition     = startswith(module.this.password_ssm_name, "/mysql/")
    error_message = "the example must publish the password under the /mysql/ prefix"
  }
}

# The example is deployable in another region by overriding one variable.
run "other_region_azs" {
  command = apply

  module {
    source = "./examples/complete"
  }

  variables {
    availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr           = "10.42.0.0/16"
  }

  assert {
    condition     = length(aws_subnet.private) == 3
    error_message = "one subnet per availability zone"
  }

  assert {
    condition     = aws_subnet.private[0].cidr_block == "10.42.0.0/24"
    error_message = "subnet CIDRs must be carved out of vpc_cidr"
  }
}
