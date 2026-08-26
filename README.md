# terraform-aws-aurora-v2

Minimal, opinionated Aurora Serverless v2 module: RDS cluster + instances, a
security group, an SSM SecureString holding the master password, and the
enhanced monitoring IAM role the cluster instances require.

## Usage

| Requirement | Version |
| --- | --- |
| terraform | `>= 1.5.0` |
| hashicorp/aws | `>= 5.96.0` |
| hashicorp/random | `>= 3.6.0` |

```hcl
module "aurora" {
  source = "./modules/terraform-aws-aurora-v2"

  vpc_id             = aws_vpc.this.id
  private_subnet_ids = aws_subnet.private[*].id

  cluster_identifier_prefix = "mysqldb-prod"
  cluster_instance_count    = 2
  database_name             = "app"
  min_capacity              = 0.5
  max_capacity              = 8

  source_security_group_ids = [aws_security_group.client.id]

  git  = "my-repo"
  tags = { Environment = "prod" }
}
```

`examples/complete` is a runnable version of the same thing: it builds its own
VPC, subnets, and client security group first.

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

20 variables, 2 of them required.

| Variable | Type | Default | Purpose |
| --- | --- | --- | --- |
| `vpc_id` | `string` | **required** | VPC the security group is created in |
| `private_subnet_ids` | `list(string)` | **required** | Subnets for the DB subnet group; at least two AZs |
| `cluster_identifier_prefix` | `string` | `"mysqldb-test"` | Name prefix for the cluster |
| `cluster_instance_count` | `number` | `1` | Number of instances; more than one gives HA |
| `database_name` | `string` | `"this"` | Initial database created on the cluster |
| `engine_version` | `string` | `"8.0.mysql_aurora.3.10.3"` | Aurora MySQL version, create time only |
| `min_capacity` | `number` | `0.5` | ACU floor; `0` enables auto pause |
| `max_capacity` | `number` | `8` | ACU ceiling; roughly 2 GiB memory per ACU |
| `enabled` | `bool` | `true` | Set to `false` to create no resources |
| `protect` | `bool` | `true` | Deletion protection, and the inverse of `apply_immediately` |
| `skip_final_snapshot` | `bool` | `false` | Skip the final snapshot on destroy |
| `kms_key_id` | `string` | `null` | CMK ARN; null uses the AWS managed `aws/rds` key |
| `git` | `string` | `"terraform-aws-aurora"` | Name of the calling Git repo, merged into tags |
| `tags` | `map(string)` | `{}` | Extra tags to merge onto every resource |
| `cidr_blocks` | `list(string)` | `["10.0.0.0/8"]` | One ingress rule per CIDR |
| `source_security_group_ids` | `list(string)` | `[]` | One ingress rule per source security group |
| `egress_cidr_blocks` | `list(string)` | `["10.0.0.0/8"]` | One egress rule per CIDR; `[]` for no egress |
| `db_cluster_parameter_group_name` | `string` | `null` | Escape hatch for cluster engine settings |
| `db_instance_parameter_group_name` | `string` | `null` | Escape hatch for instance engine settings |
| `snapshot_identifier` | `string` | `null` | Snapshot ARN to restore from at create time |

The security group rules fan out with `for_each` because
`aws_vpc_security_group_ingress_rule` takes a single CIDR or a single
referenced security group per rule. `source_security_group_ids` is keyed by
list index so a security group created in the same apply can be passed in;
append to that list rather than inserting into it.

There is no `restore_to_point_in_time` block. Do a PITR restore out of band,
then adopt the result. The snapshot restore process and its precondition are
carried over byte for byte from terraform-aws-aurora v1:

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
