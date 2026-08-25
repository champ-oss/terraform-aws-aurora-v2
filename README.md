# terraform-aws-aurora-v2

Minimal, opinionated Aurora Serverless v2 module: RDS cluster + instances, a
security group, an SSM SecureString holding the master password, and the
enhanced monitoring IAM role the cluster instances require.

## Hardcoded by design

v2 exposes 20 variables instead of 46. Everything else is hardcoded in the
first `locals` block of [main.tf](main.tf), which is the single place to change
a fleet-wide decision. The intent is that every cluster built by this module
looks the same, and upgrades happen by bumping the module version rather than
by auditing per-caller `tfvars`.

| Hardcoded | Value | Note |
| --- | --- | --- |
| `engine` / `engine_mode` | `aurora-mysql` / `provisioned` | Serverless v2 is `provisioned` plus a scaling block |
| `instance_class` | `db.serverless` | |
| `port` | `3306` | Also used by the security group rules, so they no longer wait on the cluster |
| `master_username` | `root` | 32 character random password, no special characters |
| `allow_major_version_upgrade` | `false` | |
| `auto_minor_version_upgrade` | `true` | |
| `preferred_backup_window` | `06:00-06:30` UTC | |
| `preferred_maintenance_window` | `sun:07:00-sun:07:30` UTC | |
| `backup_retention_period` | `35` days | |
| `copy_tags_to_snapshot` | `true` | |
| `storage_encrypted` | `true` | Pass `kms_key_id` for a CMK; null uses the AWS managed `aws/rds` key |
| `iam_database_authentication_enabled` | `true` | |
| `publicly_accessible` | `false` | |
| `enable_http_endpoint` | `false` | Data API off, VPC only; was `true` in v1 |
| `enabled_cloudwatch_logs_exports` | audit, error, general, slowquery | |
| `monitoring_interval` | `60` | Enhanced monitoring role is always created |
| `performance_insights_enabled` | `true` | 7 day retention, the free tier; was `false` in v1 |
| `promotion_tier` | `2` | |
| `seconds_until_auto_pause` | `300` | Only applies when `min_capacity = 0` |

The managed policy ARN for enhanced monitoring is built from
`data.aws_partition`, so it resolves correctly in GovCloud.

## The variables that remain

Required: `vpc_id`, `private_subnet_ids`.

Per-environment: `cluster_identifier_prefix`, `cluster_instance_count`,
`database_name`, `engine_version`, `git`, `tags`, `enabled`, `protect`,
`min_capacity`, `max_capacity`, `kms_key_id`, `skip_final_snapshot`.

Networking: `cidr_blocks`, `source_security_group_ids`, `egress_cidr_blocks`.

Escape hatches: `db_cluster_parameter_group_name`,
`db_instance_parameter_group_name` for engine settings the module does not
expose.

Restore: `snapshot_identifier` only. There is no `restore_to_point_in_time`
block; do a PITR restore out of band, then adopt the result.

The snapshot restore process and its precondition are carried over byte for
byte from terraform-aws-aurora v1:

- `snapshot_identifier = <snapshot ARN>` with `protect = false` and
  `skip_final_snapshot = false`, and apply
- after the restore completes, set `snapshot_identifier = null` and apply
- then set `protect = true` and apply

Two things the precondition does not enforce, both inherited from v1.
`can(startswith(var.snapshot_identifier, "arn:"))` is true for any string that
does not raise, so a bare snapshot name passes the ARN check and is handed to
the cluster unchanged. And `snapshot_identifier` is a create-only attribute, so
step two above is a change to a create-only attribute on a cluster that already
exists: run `terraform plan` and read it before applying that step.

`engine_version` stays a variable on purpose. AWS applies minor version
upgrades during the maintenance window, so the live cluster drifts ahead of
whatever the config says; it is in `ignore_changes` and only takes effect at
create time.

The SSM password parameter has no `key_id`. A `SecureString` without one is
encrypted under the AWS managed `alias/aws/ssm` key, which is why there is no
`ssm_kms_key_id` variable.

`protect` is a single knob: it sets `deletion_protection` and the inverse of
`apply_immediately`.

## Testing

Nothing is deployed to test this module. `terraform test` runs the whole suite
against mocked providers: no AWS credentials, no resources, no cost, about 7
seconds for 15 tests.

```sh
cp examples/complete/.terraform.lock.hcl .   # the root is not initialised in git
terraform init -backend=false
terraform test
```

| File | Covers |
| --- | --- |
| `tests/defaults.tftest.hcl` | every hardcoded value, asserted on the applied resource |
| `tests/wiring.tftest.hcl` | SSM parameter naming, rule fan-out, tag merge order, `enabled = false` |
| `tests/scaling.tftest.hcl` | ACU floor and ceiling, auto pause, multi-instance HA, variable pass-through |
| `tests/engine_version.tftest.hcl` | `engine_version` at create time, and instances inheriting it |
| `tests/snapshot_restore.tftest.hcl` | the restore precondition, including the cases that must fail |
| `tests/example.tftest.hcl` | `examples/complete` applied end to end |

`examples/complete` builds its own VPC, subnets, and client security group. It
looks nothing up, so the mocked suite applies the entire example with no
`override_data` and no pre-tagged infrastructure in any account.

The runs use `command = apply`, so every value a plan reports as "(known after
apply)" becomes concrete: interpolations, `merge()`, preconditions, and outputs
are all evaluated, and providers still run their own config validation. That is
the class of bug a plan cannot see.

Three limits worth knowing:

- Mocked computed attributes are fabricated. `endpoint` comes back as a random
  string, so assert that it is populated, never what it equals. Mocks also
  zero-fill computed numbers rather than returning null.
- Run blocks share state within a file. The second `apply` in a file updates
  what the first one created, which is why `engine_version` has its own file:
  `ignore_changes` correctly swallows it on update.
- Mocks never call AWS, so they cannot see an engine version that is
  unavailable in the region, a KMS policy that denies `rds.amazonaws.com`, an
  invalid parameter combination, or a quota.

For that last class, the workflow still has a real apply and destroy of
`examples/complete`, now **manual only** (`gh workflow run module`). Push and
schedule stop at the mocked suite. Dispatch it before tagging a release.

## Differences from terraform-aws-aurora

Dropped (compose these outside the module): KMS key creation, Secrets Manager,
S3 bucket + export, DMS endpoint, Glue connection, RAM share, shared snapshots,
AWS Backup, EventBridge, SNS, CloudWatch metric alarms, and the `moved` blocks.

Also dropped, because they only apply to cluster shapes this module does not
build: `availability_zones`, `backtrack_window`, `db_cluster_instance_class`,
`iops`, `storage_type`, `network_type`, `global_cluster_identifier`,
`enable_global_write_forwarding`, `replication_source_identifier`,
`source_region`, and `iam_roles` (use `aws_rds_cluster_role_association`).

The `restore_to_point_in_time` block is gone along with
`source_cluster_identifier`, `restore_to_time`, `restore_type`, and
`use_latest_restorable_time`.

Security group rules now use `aws_vpc_security_group_ingress_rule` and
`aws_vpc_security_group_egress_rule` instead of the deprecated
`aws_security_group_rule`. These take a single CIDR or a single referenced
security group per rule, so the module fans out with `for_each`:

- `cidr_blocks` -> one ingress rule per CIDR
- `source_security_group_ids` (replaces `source_security_group_id` and
  `enable_source_security_group`) -> one ingress rule per source SG, keyed by
  list index so a security group created in the same apply can be passed in;
  append to the list rather than inserting into it
- `egress_cidr_blocks` -> one egress rule per CIDR

There is no in-place migration from `aws_security_group_rule`; the old rules
must be destroyed and the new ones created, or imported by rule ID.

`egress_cidr_blocks` defaults to `["10.0.0.0/8"]`, not `0.0.0.0/0`.
