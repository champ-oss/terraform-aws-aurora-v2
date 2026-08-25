# Enhanced monitoring is the only IAM role this module needs, and it is always
# created because monitoring_interval is hardcoded on. Everything else
# (S3 export, snapshot sharing, DMS) lives outside the module.
resource "aws_iam_role" "rds_enhanced_monitoring" {
  count              = var.enabled ? 1 : 0
  name_prefix        = "rds-enhanced-monitoring-"
  assume_role_policy = data.aws_iam_policy_document.rds_enhanced_monitoring.json
  tags               = merge(local.tags, var.tags)
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  count      = var.enabled ? 1 : 0
  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = "arn:${data.aws_partition.this.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

data "aws_iam_policy_document" "rds_enhanced_monitoring" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

# Resolves to aws-us-gov in GovCloud so the managed policy ARN is correct there.
data "aws_partition" "this" {}
