resource "aws_security_group" "rds" {
  count       = var.enabled ? 1 : 0
  name_prefix = "${var.cluster_identifier_prefix}-rds-"
  description = "Aurora cluster ${var.cluster_identifier_prefix}"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, var.tags)

  lifecycle {
    create_before_destroy = true
  }
}

# Ingress from other security groups. One rule per source security group, which is
# what aws_vpc_security_group_ingress_rule requires (no list arguments).
#
# Keyed by list index, not by security group id. Callers routinely pass a client
# security group created in the same apply, and for_each cannot accept keys that
# are unknown at plan time -- it fails with "Invalid for_each argument" before
# anything is created. The tradeoff is that reordering or removing an entry
# mid-list recreates the rules after it. Append, do not insert.
resource "aws_vpc_security_group_ingress_rule" "from_sg" {
  count                        = var.enabled ? length(var.source_security_group_ids) : 0
  description                  = "ingress from security group ${var.source_security_group_ids[count.index]}"
  security_group_id            = aws_security_group.rds[0].id
  referenced_security_group_id = var.source_security_group_ids[count.index]
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
  tags                         = merge(local.tags, var.tags)

  lifecycle {
    create_before_destroy = true
  }
}

# Ingress from CIDR blocks. One rule per CIDR.
resource "aws_vpc_security_group_ingress_rule" "from_cidr" {
  for_each          = var.enabled ? toset(var.cidr_blocks) : toset([])
  description       = "ingress from cidr block ${each.value}"
  security_group_id = aws_security_group.rds[0].id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = local.port
  to_port           = local.port
  tags              = merge(local.tags, var.tags)

  lifecycle {
    create_before_destroy = true
  }
}

# There is deliberately no self referencing ingress rule. Aurora replicates
# through the shared cluster storage volume rather than between the instance
# network interfaces, so cluster members do not need to reach each other
# through this security group. Earlier revisions carried one at tcp 0-65535,
# which was surface with nothing behind it.

# Egress. One rule per CIDR. ip_protocol "-1" means all protocols and ports, and
# from_port/to_port must be omitted when it is used.
resource "aws_vpc_security_group_egress_rule" "this" {
  for_each          = var.enabled ? toset(var.egress_cidr_blocks) : toset([])
  description       = "egress to cidr block ${each.value}"
  security_group_id = aws_security_group.rds[0].id
  cidr_ipv4         = each.value
  ip_protocol       = "-1"
  tags              = merge(local.tags, var.tags)

  lifecycle {
    create_before_destroy = true
  }
}
