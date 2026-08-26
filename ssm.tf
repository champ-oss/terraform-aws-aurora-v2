resource "aws_ssm_parameter" "this" {
  count       = var.enabled ? 1 : 0
  name        = "/mysql/${aws_rds_cluster.this[0].cluster_identifier}/password"
  description = "mysql password"
  # Null key_id falls back to the AWS managed alias/aws/ssm key, which has no
  # customer controlled key policy and no rotation you can evidence. Pass a CMK
  # for any environment that has to attest to SC-12 and SC-28 over the
  # credential store.
  key_id = var.ssm_kms_key_id
  type   = "SecureString"
  value  = random_password.password[0].result
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
