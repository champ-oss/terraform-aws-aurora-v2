locals {
  normalized_snapshot_identifier = (
    can(startswith(var.snapshot_identifier, "arn:"))
    ? var.snapshot_identifier
    : null
  )
}

resource "random_password" "password" {
  count   = var.enabled ? 1 : 0
  length  = local.password_length
  special = false

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_subnet_group" "this" {
  count       = var.enabled ? 1 : 0
  name_prefix = "${var.cluster_identifier_prefix}-"
  subnet_ids  = var.private_subnet_ids
  tags        = merge(local.tags, var.tags)

  lifecycle {
    ignore_changes = [name_prefix]
  }
}

resource "aws_rds_cluster" "this" {
  count                               = var.enabled ? 1 : 0
  allow_major_version_upgrade         = local.allow_major_version_upgrade
  apply_immediately                   = !var.protect
  backup_retention_period             = local.backup_retention_period
  cluster_identifier_prefix           = "${local.cluster_identifier_prefix}-"
  copy_tags_to_snapshot               = local.copy_tags_to_snapshot
  database_name                       = var.database_name
  db_cluster_parameter_group_name     = var.db_cluster_parameter_group_name
  db_instance_parameter_group_name    = var.db_instance_parameter_group_name
  db_subnet_group_name                = aws_db_subnet_group.this[0].id
  deletion_protection                 = var.protect
  enabled_cloudwatch_logs_exports     = local.enabled_cloudwatch_logs_exports
  enable_http_endpoint                = local.enable_http_endpoint
  engine                              = local.engine
  engine_mode                         = local.engine_mode
  engine_version                      = var.engine_version
  final_snapshot_identifier           = local.snapshot_timestamp
  iam_database_authentication_enabled = local.iam_database_authentication_enabled
  kms_key_id                          = var.kms_key_id
  master_username                     = local.master_username
  master_password                     = random_password.password[0].result
  port                                = local.port
  preferred_backup_window             = local.preferred_backup_window
  preferred_maintenance_window        = local.preferred_maintenance_window
  skip_final_snapshot                 = var.skip_final_snapshot
  snapshot_identifier                 = local.normalized_snapshot_identifier
  storage_encrypted                   = local.storage_encrypted
  tags                                = merge(local.tags, var.tags)
  vpc_security_group_ids              = [aws_security_group.rds[0].id]

  serverlessv2_scaling_configuration {
    max_capacity             = var.max_capacity # increment must be equal to 0.5
    min_capacity             = var.min_capacity # increment must be equal to 0.5
    seconds_until_auto_pause = var.min_capacity != 0 ? null : local.seconds_until_auto_pause
  }

  lifecycle {
    precondition {
      condition = (
        var.snapshot_identifier == null ||
        var.snapshot_identifier == "" ||
        (
          can(startswith(var.snapshot_identifier, "arn:")) &&
          var.protect == false &&
          var.skip_final_snapshot == false
        )
      )
      error_message = <<EOT
        Invalid snapshot restore configuration.

        Either:

        - snapshot_identifier = null (or "") for normal operation

        OR

        - snapshot_identifier = <snapshot ARN>
        with:
          - protect = false
          - skip_final_snapshot = false

        After the restore completes:
        1. Set snapshot_identifier = null and apply.
        2. Set protect = true and apply.
      EOT

    }

    ignore_changes = [
      availability_zones,
      final_snapshot_identifier,
      engine_version,
      cluster_identifier_prefix
    ]
  }
}

resource "aws_rds_cluster_instance" "this" {
  count                                 = var.enabled ? var.cluster_instance_count : 0
  apply_immediately                     = !var.protect
  auto_minor_version_upgrade            = local.auto_minor_version_upgrade
  cluster_identifier                    = aws_rds_cluster.this[0].id
  copy_tags_to_snapshot                 = local.copy_tags_to_snapshot
  engine                                = aws_rds_cluster.this[0].engine
  engine_version                        = aws_rds_cluster.this[0].engine_version
  identifier_prefix                     = "${local.cluster_identifier_prefix}-"
  instance_class                        = local.instance_class
  monitoring_role_arn                   = aws_iam_role.rds_enhanced_monitoring[0].arn
  monitoring_interval                   = local.monitoring_interval
  performance_insights_enabled          = local.performance_insights_enabled
  performance_insights_retention_period = local.performance_insights_retention_period
  promotion_tier                        = local.promotion_tier
  publicly_accessible                   = local.publicly_accessible
  preferred_maintenance_window          = local.preferred_maintenance_window
  tags                                  = merge(local.tags, var.tags)

  lifecycle {
    ignore_changes = [
      engine_version,
      identifier_prefix
    ]
  }
}
