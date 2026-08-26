# Only genuine per-cluster inputs live here. Anything that should be the same
# for every Aurora cluster this module builds is hardcoded in main.tf.

# Defaults to deny. Prefer source_security_group_ids: a security group reference
# names an identity rather than an address range, which is what SC-7 and AC-4
# want to see. Use CIDRs only where a security group reference cannot reach --
# Site-to-Site VPN and Transit Gateway traffic arrives with its original source
# address and no security group in the path -- and then scope them to the
# smallest subnet that needs the port, never the whole tunnel.
variable "cidr_blocks" {
  description = "CIDR blocks allowed to connect to the database port. One aws_vpc_security_group_ingress_rule is created per entry. Defaults to none"
  type        = list(string)
  default     = []
}

variable "cluster_identifier_prefix" {
  description = "https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster#cluster_identifier_prefix"
  type        = string
  default     = "mysqldb-test"
}

variable "cluster_instance_count" {
  description = "https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_instance"
  type        = number
  default     = 1
}

variable "db_cluster_parameter_group_name" {
  description = "Cluster parameter group. The escape hatch for engine settings the module does not expose"
  type        = string
  default     = null
}

variable "db_instance_parameter_group_name" {
  description = "Instance parameter group. The escape hatch for engine settings the module does not expose"
  type        = string
  default     = null
}

# Defaults to no egress, which is the correct posture: Aurora never initiates a
# connection to a client, and the managed features this module turns on
# (CloudWatch Logs export, KMS, enhanced monitoring, Performance Insights) all
# traverse the AWS managed path rather than this security group. A cluster with
# zero egress rules works. Only add entries for something you have proven needs
# them, such as a MySQL federated engine or an outbound S3 export path.
variable "egress_cidr_blocks" {
  description = "CIDR blocks the cluster may egress to. One aws_vpc_security_group_egress_rule is created per entry. Defaults to no egress"
  type        = list(string)
  default     = []
}

variable "enabled" {
  description = "Set to false to prevent the module from creating any resources"
  type        = bool
  default     = true
}

variable "engine_version" {
  description = "Aurora MySQL version. Only applies at create time: AWS applies minor version upgrades in the maintenance window, so this is in ignore_changes and the live cluster drifts ahead of it"
  type        = string
  default     = "8.0.mysql_aurora.3.10.3"
}

variable "kms_key_id" {
  description = "ARN of the customer managed KMS key used to encrypt the cluster. Leave null to use the AWS managed aws/rds key"
  type        = string
  default     = null
}

variable "max_capacity" {
  description = "https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster#max_capacity"
  type        = number
  default     = 8 # each ACU corresponds to approximately 2 GiB of memory
}

variable "min_capacity" {
  description = "https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster#min_capacity"
  type        = number
  default     = 0.5
}

variable "private_subnet_ids" {
  description = "https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group#subnet_ids"
  type        = list(string)
}

variable "protect" {
  description = "Deletion protection. Also drives apply_immediately, which is the inverse"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster#skip_final_snapshot"
  type        = bool
  default     = false
}

variable "snapshot_identifier" {
  description = "https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster#snapshot_identifier"
  type        = string
  default     = null
}

variable "source_security_group_ids" {
  description = "Security groups allowed to connect to the database port. One aws_vpc_security_group_ingress_rule is created per entry"
  type        = list(string)
  default     = []
}

variable "ssm_kms_key_id" {
  description = "KMS key id, alias, or ARN used to encrypt the master password SSM parameter. Leave null to use the AWS managed alias/aws/ssm key"
  type        = string
  default     = null
}

variable "tags" {
  description = "Map of tags to assign to resources"
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  description = "https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group#vpc_id"
  type        = string
}
