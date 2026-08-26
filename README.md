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
  min_capacity              = 0.5
  max_capacity              = 8

  source_security_group_ids = [aws_security_group.client.id]

  tags = { Environment = "prod" }
}
```

`examples/complete` is a runnable version of the same thing: it builds its own
VPC, subnets, and client security group first.

## Hardcoded by design

v2 exposes 19 variables instead of 46. Everything else is hardcoded in the
first `locals` block of [main.tf](main.tf), which is the single place to change
a fleet-wide decision. The intent is that every cluster built by this module
looks the same, and upgrades happen by bumping the module version rather than
by auditing per-caller `tfvars`.

| Hardcoded | Value | Note |
| --- | --- | --- |
| `engine` / `engine_mode` | `aurora-mysql` / `provisioned` | Serverless v2 is `provisioned` plus a scaling block |
| `instance_class` | `db.serverless` | |
| `database_name` | `this` | Create the schemas the application needs from migrations, not from module inputs |
| `port` | `3306` | Also used by the security group rules, so they no longer wait on the cluster |
| `master_username` | `root` | 32 character random password, no special characters |
| SSM parameter path | `/mysql/<cluster identifier>/password` | Read it from the `password_ssm_name` output rather than rebuilding it |
| `name` tag | `cluster_identifier_prefix` | Derived, not a variable of its own |
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

19 variables, 2 of them required.

| Variable | Type | Default | Purpose |
| --- | --- | --- | --- |
| `vpc_id` | `string` | **required** | VPC the security group is created in |
| `private_subnet_ids` | `list(string)` | **required** | Subnets for the DB subnet group; at least two AZs |
| `cluster_identifier_prefix` | `string` | `"mysqldb-test"` | Name prefix for the cluster |
| `cluster_instance_count` | `number` | `1` | Number of instances; more than one gives HA |
| `engine_version` | `string` | `"8.0.mysql_aurora.3.10.3"` | Aurora MySQL version, create time only |
| `min_capacity` | `number` | `0.5` | ACU floor; `0` enables auto pause |
| `max_capacity` | `number` | `8` | ACU ceiling; roughly 2 GiB memory per ACU |
| `enabled` | `bool` | `true` | Set to `false` to create no resources |
| `protect` | `bool` | `true` | Deletion protection, and the inverse of `apply_immediately` |
| `skip_final_snapshot` | `bool` | `false` | Skip the final snapshot on destroy |
| `kms_key_id` | `string` | `null` | CMK ARN; null uses the AWS managed `aws/rds` key |
| `tags` | `map(string)` | `{}` | Extra tags to merge onto every resource |
| `cidr_blocks` | `list(string)` | `[]` | One ingress rule per CIDR; empty by default |
| `source_security_group_ids` | `list(string)` | `[]` | One ingress rule per source security group |
| `egress_cidr_blocks` | `list(string)` | `[]` | One egress rule per CIDR; no egress by default |
| `db_cluster_parameter_group_name` | `string` | `null` | Escape hatch for cluster engine settings |
| `db_instance_parameter_group_name` | `string` | `null` | Escape hatch for instance engine settings |
| `snapshot_identifier` | `string` | `null` | Snapshot ARN to restore from at create time |
| `ssm_kms_key_id` | `string` | `null` | CMK for the password parameter; null uses the AWS managed `aws/ssm` key |

The security group rules fan out with `for_each` because
`aws_vpc_security_group_ingress_rule` takes a single CIDR or a single
referenced security group per rule. `source_security_group_ids` is keyed by
list index so a security group created in the same apply can be passed in;
append to that list rather than inserting into it.

## The security group defaults to deny

`cidr_blocks` and `egress_cidr_blocks` are both empty, so a caller who passes
nothing gets a cluster reachable by nothing. The obvious alternative -- letting
them default to the RFC 1918 supernet, as v1 did -- is 16.7 million addresses
on 3306 in one direction and every protocol and port in the other, which is a
finding under SC-7 and AC-4 regardless of how private the subnet is.

Reach the cluster with `source_security_group_ids`. A security group reference
names an identity rather than an address range, which is both tighter and
easier to evidence. Two things do not work that way and need CIDRs:
Site-to-Site VPN and Transit Gateway traffic, which arrives with its original
source address and no security group anywhere in the path. Scope those to the
smallest subnet that actually needs the port.

AWS Client VPN does work with a security group reference. Client VPN creates
network interfaces in the subnets it is associated with, those interfaces carry
a security group you control, and client traffic is translated to them -- so
pass the Client VPN endpoint's security group in `source_security_group_ids`
alongside the ECS service's, and leave `cidr_blocks` empty:

```hcl
module "aurora" {
  source = "github.com/champ-oss/terraform-aws-aurora-v2"

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids

  # index keyed, so append only -- never insert or reorder
  source_security_group_ids = [
    aws_security_group.fargate_service.id, # 0
    aws_security_group.client_vpn.id,      # 1
  ]
}
```

Egress stays empty. Aurora never initiates a connection to a client, and the
managed features this module turns on -- CloudWatch Logs export, KMS, enhanced
monitoring, Performance Insights -- traverse the AWS managed path rather than
this security group. A cluster with no egress rules works.

There is no self referencing rule either. Aurora replicates through the shared
cluster storage volume rather than between the instance network interfaces, so
cluster members have no reason to reach each other through this security group.
The upshot is that a caller who passes neither list gets a security group with
zero rules on it, and every rule that does exist is one somebody asked for by
name.

What the security group cannot do is force TLS. It allows 3306; the engine
still accepts plaintext on that port unless `require_secure_transport` is `ON`,
which is a cluster parameter group setting and therefore goes through
`db_cluster_parameter_group_name`. Clients have to verify the RDS CA as well.

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

## There is no `name` variable

The `name` tag and the SSM parameter path are both derived. `name` is
`cluster_identifier_prefix`, which is already the caller's name for the
cluster, so a separate variable was two inputs for one idea and two chances for
them to disagree. It has to stay derived from the *variable* rather than read
back off `aws_rds_cluster.this[0].cluster_identifier`, because `local.tags` is
applied to that cluster and reading it back would be a dependency cycle.

The password parameter is at `/mysql/<cluster identifier>/password`. The
identifier already carries `cluster_identifier_prefix` plus a random suffix, so
it is unique per cluster without a caller-supplied namespace in front of it.
Scope IAM to it with `parameter/mysql/<your prefix>-*`, and read the exact path
from the `password_ssm_name` output rather than rebuilding the string.

`database_name` is hardcoded to `this`. It only names the one schema Aurora
creates at cluster creation; anything the application actually needs should
come from migrations that run against the cluster, not from a module input that
can only ever take effect once.

The SSM password parameter takes `ssm_kms_key_id`. Left null, the
`SecureString` is encrypted under the AWS managed `alias/aws/ssm` key, which
has no customer controlled key policy and no rotation you can evidence -- pass
a CMK anywhere the credential store has to attest to SC-12 and SC-28. Note that
`iam_database_authentication_enabled` is hardcoded on, so the stronger option is
to have callers authenticate with IAM and treat this parameter as break glass.

## Testing

Nothing is deployed to test this module. `terraform test` runs the whole suite
against mocked providers: no AWS credentials, no resources, no cost, about 8
seconds for 17 tests.

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
