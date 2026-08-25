# Serverless v2 scaling, HA topology, and the inputs that are still variables.

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

run "default_scaling" {
  command = apply

  assert {
    condition     = aws_rds_cluster.this[0].serverlessv2_scaling_configuration[0].min_capacity == 0.5
    error_message = "default min capacity must be 0.5 ACU"
  }

  assert {
    condition     = aws_rds_cluster.this[0].serverlessv2_scaling_configuration[0].max_capacity == 8
    error_message = "default max capacity must be 8 ACU"
  }

  # Auto pause only applies when the floor is zero, so it must not be
  # configured here. Mocked providers zero-fill computed numbers instead of
  # returning null, so accept either as "not set".
  assert {
    condition = anytrue([
      aws_rds_cluster.this[0].serverlessv2_scaling_configuration[0].seconds_until_auto_pause == null,
      aws_rds_cluster.this[0].serverlessv2_scaling_configuration[0].seconds_until_auto_pause == 0,
    ])
    error_message = "auto pause must not be set when min_capacity is above 0"
  }
}

run "scale_to_zero_sets_auto_pause" {
  command = apply

  variables {
    min_capacity = 0
    max_capacity = 16
  }

  assert {
    condition     = aws_rds_cluster.this[0].serverlessv2_scaling_configuration[0].seconds_until_auto_pause == 300
    error_message = "auto pause must be set when min_capacity is 0"
  }

  assert {
    condition     = aws_rds_cluster.this[0].serverlessv2_scaling_configuration[0].max_capacity == 16
    error_message = "max capacity must follow the variable"
  }
}

run "multi_instance_is_ha" {
  command = apply

  variables {
    cluster_instance_count = 3
  }

  assert {
    condition     = length(aws_rds_cluster_instance.this) == 3
    error_message = "one instance per cluster_instance_count"
  }

  assert {
    condition     = length(distinct(aws_rds_cluster_instance.this[*].identifier)) == 3
    error_message = "instance identifiers must be distinct"
  }

  assert {
    condition     = alltrue([for i in aws_rds_cluster_instance.this : i.cluster_identifier == aws_rds_cluster.this[0].id])
    error_message = "every instance must join the cluster"
  }

  assert {
    condition     = length(output.instance_identifiers) == 3
    error_message = "instance_identifiers output must list every instance"
  }
}

# Run blocks in a file share state, so this one updates the cluster the runs
# above created rather than building a fresh one.
run "variables_reach_the_cluster" {
  command = apply

  variables {
    database_name  = "this"
    engine_version = "8.0.mysql_aurora.3.09.0"
    kms_key_id     = "arn:aws:kms:us-east-1:111122223333:key/abcd-1234"
  }

  assert {
    condition     = aws_rds_cluster.this[0].database_name == "this"
    error_message = "database_name must reach the cluster"
  }

  # This is the drift protection, asserted. Because run blocks share state this
  # is an update to an existing cluster, and ignore_changes must swallow the new
  # engine_version rather than scheduling an upgrade. Create-time behaviour is
  # covered in engine_version.tftest.hcl.
  assert {
    condition     = aws_rds_cluster.this[0].engine_version == "8.0.mysql_aurora.3.10.3"
    error_message = "ignore_changes must keep an existing cluster off a new engine_version"
  }

  assert {
    condition     = aws_rds_cluster.this[0].kms_key_id == "arn:aws:kms:us-east-1:111122223333:key/abcd-1234"
    error_message = "kms_key_id must reach the cluster"
  }

  assert {
    condition     = aws_db_subnet_group.this[0].subnet_ids == toset(["subnet-0aaa", "subnet-0bbb"])
    error_message = "the subnet group must use the supplied subnets"
  }
}
