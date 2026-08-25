# engine_version at create time. It needs its own file because run blocks share
# state within a file, and ignore_changes makes the value a no-op on update.

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
  engine_version     = "8.0.mysql_aurora.3.09.0"
}

run "engine_version_applies_at_create" {
  command = apply

  assert {
    condition     = aws_rds_cluster.this[0].engine_version == "8.0.mysql_aurora.3.09.0"
    error_message = "engine_version must be honoured when the cluster is created"
  }

  # Instances follow the cluster rather than carrying their own pinned version.
  assert {
    condition     = aws_rds_cluster_instance.this[0].engine_version == aws_rds_cluster.this[0].engine_version
    error_message = "instances must inherit the cluster engine version"
  }

  assert {
    condition     = aws_rds_cluster_instance.this[0].engine == aws_rds_cluster.this[0].engine
    error_message = "instances must inherit the cluster engine"
  }
}
