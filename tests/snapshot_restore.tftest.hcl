# The snapshot restore process, carried over from terraform-aws-aurora v1. The
# precondition in rds.tf is byte-identical to v1's, and these tests pin the
# behaviour it actually produces -- including the parts where that differs from
# what the error message says.
#
# Deliberately NOT tested here: whether changing snapshot_identifier replaces
# the cluster. mock_provider does not model replacement -- RequiresReplace comes
# from the real provider's PlanResourceChange, which mocks never call, so a
# ForceNew attribute can be changed under mocks with no replacement reported.
# Verify that with a real `terraform plan` and read the output.

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
  private_subnet_ids = ["subnet-0aaa"]
}

# null is the only value that reaches the cluster as null: can(startswith(null,
# "arn:")) errors, so the normalization falls through to null.
run "no_restore_by_default" {
  command = apply

  assert {
    condition     = aws_rds_cluster.this[0].snapshot_identifier == null
    error_message = "snapshot_identifier must be null on a normal apply"
  }
}

# Both halves of the v1 precondition, each failing on its own.
run "restore_requires_protect_off" {
  command = plan

  variables {
    snapshot_identifier = "arn:aws:rds:us-east-1:111122223333:cluster-snapshot:snap"
    protect             = true
    skip_final_snapshot = false
  }

  expect_failures = [aws_rds_cluster.this]
}

run "restore_requires_skip_final_snapshot_off" {
  command = plan

  variables {
    snapshot_identifier = "arn:aws:rds:us-east-1:111122223333:cluster-snapshot:snap"
    protect             = false
    skip_final_snapshot = true
  }

  expect_failures = [aws_rds_cluster.this]
}

run "restore_with_protect_off_is_allowed" {
  command = apply

  variables {
    snapshot_identifier = "arn:aws:rds:us-east-1:111122223333:cluster-snapshot:snap"
    protect             = false
    skip_final_snapshot = false
  }

  assert {
    condition     = aws_rds_cluster.this[0].snapshot_identifier == "arn:aws:rds:us-east-1:111122223333:cluster-snapshot:snap"
    error_message = "the snapshot must be passed through to the cluster"
  }

  # protect = false also flips apply_immediately on.
  assert {
    condition     = aws_rds_cluster.this[0].apply_immediately == true
    error_message = "apply_immediately must be on when protect is off"
  }

  assert {
    condition     = aws_rds_cluster.this[0].deletion_protection == false
    error_message = "deletion protection must be off during a restore"
  }
}

# The error message asks for an ARN, but can(startswith(...)) returns true for
# any string that does not error, so a bare snapshot name is passed through
# unchanged. Pinning it because it is v1 behaviour, not because it is intended.
run "bare_snapshot_name_is_passed_through" {
  command = apply

  variables {
    snapshot_identifier = "mysqldb-test-20260101000000"
    protect             = false
    skip_final_snapshot = false
  }

  assert {
    condition     = aws_rds_cluster.this[0].snapshot_identifier == "mysqldb-test-20260101000000"
    error_message = "a bare snapshot name is passed through, ARN or not"
  }
}
