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
    cluster_identifier_prefix = "some-cluster"
    cidr_blocks               = ["10.1.0.0/16", "10.2.0.0/16"]
    egress_cidr_blocks        = ["10.0.0.0/8"]
    source_security_group_ids = ["sg-0aaa", "sg-0bbb", "sg-0ccc"]
    tags                      = { env = "test" }
  }

  # The parameter name interpolates cluster_identifier, which is unknown until
  # apply. A plan can only tell you the name will exist.
  assert {
    condition     = startswith(aws_ssm_parameter.this[0].name, "/mysql/")
    error_message = "SSM parameter is not under the /mysql/ prefix"
  }

  assert {
    condition     = endswith(aws_ssm_parameter.this[0].name, "/password")
    error_message = "SSM parameter name must end in /password"
  }

  # The cluster identifier is the only thing distinguishing one cluster's
  # parameter from another's now that there is no name variable.
  assert {
    condition     = aws_ssm_parameter.this[0].name == "/mysql/${aws_rds_cluster.this[0].cluster_identifier}/password"
    error_message = "SSM parameter path must be /mysql/<cluster identifier>/password"
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
  # The name tag is derived from cluster_identifier_prefix, not passed in.
  assert {
    condition     = aws_rds_cluster.this[0].tags["name"] == "some-cluster"
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

# The module's own defaults are part of its security posture, so they are
# asserted rather than left to whoever reads variables.tf. Nothing here passes a
# single variable: this is what a caller gets for free.
run "defaults_deny" {
  command = apply

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.from_cidr) == 0
    error_message = "cidr_blocks must default to no ingress"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.from_sg) == 0
    error_message = "source_security_group_ids must default to no ingress"
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.this) == 0
    error_message = "egress_cidr_blocks must default to no egress"
  }

  # There is no self referencing rule either, so a default cluster has an empty
  # security group. Every rule on it is one a caller asked for by name.
  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.from_cidr) + length(aws_vpc_security_group_ingress_rule.from_sg) + length(aws_vpc_security_group_egress_rule.this) == 0
    error_message = "a default cluster must have no security group rules at all"
  }
}

# Only the CMK path is asserted. key_id is a computed attribute, so the mock
# provider invents a value for it when the config leaves it null, and the
# default path has nothing stable to compare against.
run "ssm_cmk" {
  command = apply

  variables {
    ssm_kms_key_id = "arn:aws:kms:us-east-1:111122223333:key/abcd-1234"
  }

  assert {
    condition     = aws_ssm_parameter.this[0].key_id == "arn:aws:kms:us-east-1:111122223333:key/abcd-1234"
    error_message = "ssm_kms_key_id must reach the SSM parameter"
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
