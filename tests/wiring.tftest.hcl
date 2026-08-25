# Wiring that a plan cannot check, because the values it depends on are
# "(known after apply)" until something actually applies.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

mock_provider "random" {}

variables {
  vpc_id             = "vpc-0123456789abcdef0"
  private_subnet_ids = ["subnet-0aaa", "subnet-0bbb"]
}

run "ssm_and_security_group_fanout" {
  command = apply

  variables {
    git                       = "some-repo"
    cidr_blocks               = ["10.1.0.0/16", "10.2.0.0/16"]
    egress_cidr_blocks        = ["10.0.0.0/8"]
    source_security_group_ids = ["sg-0aaa", "sg-0bbb", "sg-0ccc"]
    tags                      = { env = "test" }
  }

  # The parameter name interpolates cluster_identifier, which is unknown until
  # apply. A plan can only tell you the name will exist.
  assert {
    condition     = startswith(aws_ssm_parameter.this[0].name, "/some-repo/mysql/")
    error_message = "SSM parameter is not under the /<git>/mysql/ prefix"
  }

  assert {
    condition     = endswith(aws_ssm_parameter.this[0].name, "/password")
    error_message = "SSM parameter name must end in /password"
  }

  assert {
    condition     = aws_ssm_parameter.this[0].type == "SecureString"
    error_message = "the password must be a SecureString"
  }

  # One rule per entry, and no rule collapsing into another.
  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.from_cidr) == 2
    error_message = "expected one ingress rule per cidr block"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.from_sg) == 3
    error_message = "expected one ingress rule per source security group"
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.this) == 1
    error_message = "expected one egress rule per egress cidr block"
  }

  # Rules use the hardcoded port, not a value read back off the cluster.
  assert {
    condition = alltrue([
      for r in values(aws_vpc_security_group_ingress_rule.from_cidr) : r.from_port == 3306 && r.to_port == 3306
    ])
    error_message = "ingress rules must open 3306"
  }

  # Module tags survive the caller's tags. Flip these if var.tags should win.
  assert {
    condition     = aws_rds_cluster.this[0].tags["git"] == "some-repo"
    error_message = "module tags must be applied"
  }

  assert {
    condition     = aws_rds_cluster.this[0].tags["env"] == "test"
    error_message = "caller tags must be applied"
  }

  assert {
    condition     = output.endpoint != "" && output.port != "" && output.password_ssm_name != ""
    error_message = "outputs must be populated"
  }
}

run "no_egress" {
  command = apply

  variables {
    egress_cidr_blocks = []
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.this) == 0
    error_message = "an empty egress list must create no egress rules"
  }
}

run "disabled_creates_nothing" {
  command = apply

  variables {
    enabled = false
  }

  assert {
    condition     = length(aws_rds_cluster.this) == 0 && length(aws_rds_cluster_instance.this) == 0
    error_message = "enabled = false must create no cluster"
  }

  assert {
    condition     = length(aws_ssm_parameter.this) == 0 && length(aws_security_group.rds) == 0 && length(aws_iam_role.rds_enhanced_monitoring) == 0
    error_message = "enabled = false must create no supporting resources"
  }

  # Every output has to survive the resource being absent.
  assert {
    condition     = output.arn == "" && output.endpoint == "" && output.security_group_id == ""
    error_message = "string outputs must degrade to empty when disabled"
  }

  assert {
    condition     = length(output.instance_identifiers) == 0 && length(output.cluster_members) == 0
    error_message = "list outputs must degrade to empty when disabled"
  }
}
