resource "aws_ssm_parameter" "this" {
  count       = var.enabled ? 1 : 0
  name        = "/${var.git}/mysql/${aws_rds_cluster.this[0].cluster_identifier}/password"
  description = "mysql password"
  # No key_id, so this is encrypted with the AWS managed alias/aws/ssm key.
  type  = "SecureString"
  value = random_password.password[0].result
  tags = merge({
    master_username    = aws_rds_cluster.this[0].master_username
    port               = aws_rds_cluster.this[0].port
    endpoint           = aws_rds_cluster.this[0].endpoint
    cluster_identifier = aws_rds_cluster.this[0].cluster_identifier
    read_only_endpoint = aws_rds_cluster.this[0].reader_endpoint
  }, local.tags, var.tags)

  lifecycle {
    create_before_destroy = true
  }
}
