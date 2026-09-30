# terraform-aws-docdb-cluster

Terraform module for an Amazon DocumentDB cluster — a MongoDB-compatible
document store built as a set of instances over shared, replicated
storage, with an endpoint that follows the primary across a failover.

## Cost

DocumentDB bills per instance-hour for every instance in the cluster,
per gigabyte-month of cluster storage, per million I/O operations
against that storage, and for backup storage beyond the free allotment
equal to the cluster's storage size. Each added `instance_count` is a
full instance-hour charge, so a three-instance cluster costs three times
a single-instance one for compute while sharing one copy of the storage.
Setting `storage_type` to `'iopt1'` replaces the per-I/O charge with a
higher storage rate, which is the cheaper shape for an I/O-heavy
workload. Data transfer out of the Region is billed separately. See
AWS's
[Amazon DocumentDB pricing](https://aws.amazon.com/documentdb/pricing/)
page for current rates.

## Design

The cluster and its instances are bundled into one module because they
are never useful apart: a cluster with no instances serves no traffic,
the instances are homogeneous, and nothing outside the module references
one specific member — applications connect through the cluster's primary
or reader endpoint, not to a named instance. This is the same bundling
reasoning as
[`terraform-aws-rds-cluster`](https://github.com/kn47ytv9mv/terraform-aws-rds-cluster)
and its instances. Settings AWS models per-instance (`instance_class`,
`promotion_tier`, Performance Insights, the instance maintenance window)
are applied identically to every instance; a cluster whose members must
genuinely differ is past what this module covers.

`instance_count` defaults to 1, which is a single primary and no
failover target. Raise it to at least 2, and preferably 3 spread across
three availability zones, for a cluster that must survive losing its
primary without downtime. Setting it to 0 creates the cluster volume
with no compute attached, which is the shape AWS's own CLI produces.

The cluster identifier must begin with a letter, so a bare random UUID
is not usable as the generated fallback — ten of the sixteen possible
first characters are digits, and AWS rejects every one of those. The
fallback is therefore `docdb-` followed by the UUID, deliberately
distinct from the `db-` prefix
[`terraform-aws-rds-cluster`](https://github.com/kn47ytv9mv/terraform-aws-rds-cluster)
uses, because cluster identifiers share a single namespace across Amazon
RDS, Amazon Neptune, and Amazon DocumentDB within an account and Region.

### Subnet groups

Point `db_subnet_group_name` at
[`terraform-aws-db-subnet-group`](https://github.com/kn47ytv9mv/terraform-aws-db-subnet-group).
Amazon DocumentDB shares its DB subnet groups with Amazon RDS — AWS
documents subnet groups in the table of
[Regional quotas shared among Amazon DocumentDB and Amazon RDS](https://docs.aws.amazon.com/documentdb/latest/developerguide/limits.html),
and a cluster created with no subnet group lands in the Region's
`default` group, which RDS owns. There is no DocumentDB-specific subnet
group module in this family because there is no DocumentDB-specific
subnet group to build.

Span at least two availability zones, and preferably exactly three.
DocumentDB selects three zones when the cluster is created and then
refuses an instance placed in any zone outside that set, so a group
listing more than three leaves the extra zones unusable for this
cluster.

### Passwords

Three mutually exclusive options, in descending order of preference:
`manage_master_user_password` (AWS generates, stores, and rotates the
password in Secrets Manager — no password passes through Terraform),
`master_password_wo` with `master_password_wo_version` (write-only,
sent during apply but never persisted to state), and `master_password`
(stored in state in plain text). See the `master_user_secret` output for
the secret AWS creates under the first option.

DocumentDB supports the first option with one gap relative to Aurora:
this resource offers no argument for choosing the KMS key that encrypts
the generated secret, so the account's AWS-managed key for Secrets
Manager is always used. A cluster that must hold its primary credential
under a customer-managed key has to use `master_password_wo` and a
secret managed separately with
[`terraform-aws-secretsmanager-secret`](https://github.com/kn47ytv9mv/terraform-aws-secretsmanager-secret).

### Encryption

`storage_encrypted` defaults to true, which is a deliberate deviation
from the AWS CLI's own default. Encryption cannot be turned on for an
existing cluster: an unencrypted cluster has to be snapshotted and the
snapshot restored into a new encrypted cluster, with a cutover and
whatever downtime that implies. The cost of defaulting it on is that a
caller who genuinely wants unencrypted storage must say so; the cost of
defaulting it off is a migration. Leave `kms_key_id` null to use AWS's
managed key for RDS, or supply a key from
[`terraform-aws-kms-key`](https://github.com/kn47ytv9mv/terraform-aws-kms-key)
to control the key policy and rotation yourself.

### Log exports

`enabled_cloudwatch_logs_exports` accepts exactly two values, `'audit'`
and `'profiler'`. These are DocumentDB's own log types and share nothing
with the RDS set — `'error'`, `'general'`, `'slowquery'`, and
`'postgresql'` are all rejected. The audit log records authentication
and data-definition events; the profiler log records operations slower
than a configured threshold.

Naming a log type here only turns on the export. Generating the log
itself is a parameter-group setting, so both types also require a custom
cluster parameter group from
[`terraform-aws-docdb-cluster-parameter-group`](https://github.com/kn47ytv9mv/terraform-aws-docdb-cluster-parameter-group):
`'audit'` needs `audit_logs` enabled, and `'profiler'` needs `profiler`
enabled together with `profiler_threshold_ms` and
`profiler_sampling_rate`. Exporting a log type without its parameter
produces an empty log group rather than an error, which is why this
module leaves the export off by default rather than turning on something
that would silently do nothing.

### Destroying the cluster

`skip_final_snapshot` and `final_snapshot_identifier` interact, exactly
as in the Aurora sibling. `skip_final_snapshot` defaults to false so a
single destroy cannot lose the data, which means
`final_snapshot_identifier` is required — AWS refuses the deletion
otherwise, and it refuses it at teardown time rather than at plan time.
A `validation` block therefore rejects the combination up front, so the
failure arrives before anything is created rather than when the cluster
is already gone from the configuration. Set `skip_final_snapshot` to
true for a cluster whose contents are genuinely disposable.

`deletion_protection` defaults to false, because enabling it makes
`terraform destroy` fail until a separate apply turns it off again. Note
that AWS's console enables it by default while the CLI does not, so a
cluster created in the console and imported will arrive with it on.

### How this relates to MongoDB

DocumentDB is not MongoDB. It is a purpose-built engine that emulates
the MongoDB API over the MongoDB wire protocol, so MongoDB drivers,
`mongosh`, and most application code connect to it unchanged. AWS states
that DocumentDB "is compatible with the MongoDB 3.6, 4.0, 5.0, and 8.0
APIs" and that it "emulates" them; `engine_version` selects which level
a cluster presents. That compatibility is a documented subset, not
parity: AWS maintains a list of
[supported APIs, operations, and data types](https://docs.aws.amazon.com/documentdb/latest/developerguide/mongo-apis.html)
and a list of
[functional differences](https://docs.aws.amazon.com/documentdb/latest/developerguide/functional-differences.html),
and the differences reach behavior an application can depend on —
result sets are not implicitly ordered, `$vectorSearch` is not a
standalone operator, the `admin` and `local` databases do not exist, and
retryable writes only work from engine version 8.0.2 onward.

For a caller choosing between this, self-managed MongoDB, and MongoDB
Atlas: DocumentDB is the right answer when the value is in AWS-native
operations — storage that replicates six ways across three availability
zones, backups and point-in-time restore through the same controls as
the rest of an AWS estate, IAM and KMS integration, and no engine to
patch. Self-managed MongoDB or Atlas is the right answer when the
application needs the parts of MongoDB that DocumentDB does not
implement, a MongoDB version newer than the emulated levels, sharding
semantics, or portability off AWS. Verify the specific operations an
application issues against AWS's supported-API list before migrating;
compatibility at the driver level does not imply compatibility at the
query level.

### Deliberately not covered

Elastic clusters — DocumentDB's sharded, storage-and-compute-decoupled
variant — are a separate resource with a separate cost model and are not
exposed here. Neither is the cluster's
`serverless_v2_scaling_configuration`, nor `cluster_members`, which
duplicates what `instance_count` already governs. Global clusters are
joined through `global_cluster_identifier` but are not created by this
module.

There is no `publicly_accessible` input because DocumentDB does not
offer one: the provider models the attribute as read-only, and a
DocumentDB cluster is reachable only from inside its VPC or through a
bastion, VPN, or Direct Connect. There is no
`iam_database_authentication_enabled` input either — DocumentDB
authenticates with its own users and role-based access control rather
than with IAM database authentication.

## Usage

```hcl
module "cluster" {
  source = "kn47ytv9mv/docdb-cluster/aws"

  engine_version = "5.0.0"
  instance_class = "db.r6g.large"
  instance_count = 3

  master_username             = "app"
  manage_master_user_password = true

  db_subnet_group_name   = module.subnet_group.name
  vpc_security_group_ids = [module.security_group.id]

  db_cluster_parameter_group_name = "production-docdb"
  enabled_cloudwatch_logs_exports = ["audit", "profiler"]

  final_snapshot_identifier = "app-final"
}
```

Or directly from this repository, as a single I/O-optimized instance for
a development environment:

```hcl
module "cluster" {
  source = "github.com/kn47ytv9mv/terraform-aws-docdb-cluster"

  cluster_identifier = "analytics"
  instance_class     = "db.t4g.medium"

  master_username             = "app"
  manage_master_user_password = true

  storage_type            = "iopt1"
  backup_retention_period = 14

  skip_final_snapshot = true
}
```

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.11 |
| aws | ~> 6.61 |
| random | ~> 3.9 |

## Providers

| Name | Version |
|---|---|
| aws | ~> 6.61 |
| random | ~> 3.9 |

## Inputs

| Name | Description | Default | Required |
|---|---|---|---|
| cluster_identifier | Identifier of the cluster. Must begin with a letter, hold only lowercase alphanumeric characters and hyphens, end alphanumerically, and be at most 63 characters. Unique across Amazon RDS, Neptune, and DocumentDB per account and Region. If null, a unique identifier is generated. | `null` | no |
| engine | Cluster engine. DocumentDB has exactly one, `'docdb'`. Cannot be changed after creation. | `"docdb"` | no |
| engine_version | Engine version (for example `'5.0.0'` or `'8.0.0'`), naming the MongoDB API version the cluster emulates. If null, AWS picks its own current default, which moves between major versions. | `null` | no |
| instance_count | Number of instances in the cluster, 0 to 16. The first is the primary; every other is a promotable replica. Raise to at least 2 to survive losing the primary without downtime. | `1` | no |
| instance_class | Compute and memory capacity of each cluster instance (for example `'db.r6g.large'`). | `null` | no |
| master_username | Primary user name, 1 to 63 alphanumeric characters beginning with a letter. Cannot be changed without replacing the cluster. | `null` | no |
| master_password | Primary user password, 8 to 100 printable ASCII characters excluding `/`, `"`, and `@`. Stored in state in plain text — prefer `manage_master_user_password` or `master_password_wo`. | `null` | no |
| master_password_wo | Primary user password as a write-only value, never persisted to state. Requires `master_password_wo_version`. | `null` | no |
| master_password_wo_version | Version counter for `master_password_wo`. Increment it to push a changed password. | `null` | no |
| manage_master_user_password | Whether AWS generates the primary user password and manages it in Secrets Manager, including rotation. The recommended option. Always uses the AWS-managed key for Secrets Manager — see Design. | `null` | no |
| storage_encrypted | Whether cluster storage is encrypted at rest. Defaults true because encryption cannot be turned on for an existing cluster. | `true` | no |
| kms_key_id | ARN of the KMS key encrypting cluster storage, from `terraform-aws-kms-key`. Only used when `storage_encrypted` is true. | `null` | no |
| storage_type | Cluster storage configuration, `'standard'` or `'iopt1'`. I/O-optimized replaces the per-I/O charge with a higher storage rate. | `null` | no |
| db_subnet_group_name | Name of the subnet group placing this cluster in a VPC, from `terraform-aws-db-subnet-group` — DocumentDB shares DB subnet groups with Amazon RDS. If null, the Region's default group is used. | `null` | no |
| vpc_security_group_ids | IDs of the security groups controlling network access, from `terraform-aws-vpc-security-groups`. Each must permit inbound traffic on the cluster's port. | `null` | no |
| availability_zones | Availability zones the cluster may place instances in. DocumentDB selects three regardless and rejects an instance outside that set. | `null` | no |
| port | Port the cluster accepts connections on; every instance uses the same one. If null, DocumentDB's default (27017) applies. | `null` | no |
| db_cluster_parameter_group_name | Name of the cluster parameter group, from `terraform-aws-docdb-cluster-parameter-group`. Required to turn on audit or profiler logging. | `null` | no |
| backup_retention_period | Days of automated backups retained, 1 to 35. Defaults to 7 rather than AWS's own default of 1. | `7` | no |
| preferred_backup_window | Daily UTC window automated backups are taken in (for example `'03:00-04:00'`). Must not overlap `preferred_maintenance_window`. | `null` | no |
| preferred_maintenance_window | Weekly UTC window AWS applies cluster maintenance in (for example `'sun:05:00-sun:06:00'`). | `null` | no |
| instance_preferred_maintenance_window | Weekly UTC window AWS patches each instance in, separate from the cluster window and applied identically to every instance. | `null` | no |
| skip_final_snapshot | Whether destroying the cluster skips taking a final snapshot. Defaults false, which makes `final_snapshot_identifier` required. | `false` | no |
| final_snapshot_identifier | Name of the snapshot taken when the cluster is destroyed. Required unless `skip_final_snapshot` is true. | `null` | no |
| deletion_protection | Whether AWS refuses to delete the cluster while set. Enabling it makes `terraform destroy` fail until a separate apply turns it off. | `false` | no |
| auto_minor_version_upgrade | Whether AWS applies minor engine upgrades to each instance automatically during its maintenance window. | `null` | no |
| allow_major_version_upgrade | Whether a change to `engine_version` crossing a major version is permitted. A major upgrade changes the emulated MongoDB API version. | `null` | no |
| apply_immediately | Whether modifications are applied immediately rather than deferred to the next maintenance window. Immediate application can cause downtime. | `null` | no |
| enabled_cloudwatch_logs_exports | Log types exported to CloudWatch Logs. DocumentDB supports only `'audit'` and `'profiler'`, each of which also needs its parameter set in the cluster parameter group. | `null` | no |
| enable_performance_insights | Whether Performance Insights collects database load metrics on each instance. | `null` | no |
| performance_insights_kms_key_id | ARN of the KMS key encrypting Performance Insights data. | `null` | no |
| promotion_tier | Failover priority of each instance, 0 to 15. Applied identically to every instance this module creates. | `null` | no |
| ca_cert_identifier | Certificate authority bundle used for each instance's TLS certificate (for example `'rds-ca-rsa2048-g1'`). | `null` | no |
| snapshot_identifier | Identifier or ARN of a snapshot to restore this cluster from, instead of creating an empty one. | `null` | no |
| restore_to_point_in_time | Restore this cluster from another cluster's continuous backups. Set either `restore_to_time` or `use_latest_restorable_time`. Changing any field replaces the cluster. | `null` | no |
| global_cluster_identifier | Identifier of a DocumentDB global cluster to join this cluster to. A secondary member sets neither `master_username` nor a password. | `null` | no |
| tags | A map of tags to assign to the cluster and every instance in it. | `null` | no |

## Outputs

| Name | Description |
|---|---|
| id | The ID of the cluster. |
| arn | The ARN of the cluster. DocumentDB clusters live in the RDS ARN namespace. |
| cluster_identifier | The identifier of the cluster. |
| endpoint | Primary endpoint of the cluster. Point a MongoDB driver here — it follows the current primary across a failover. |
| reader_endpoint | Reader endpoint, load-balancing across replicas. Use it with a read preference of `secondaryPreferred`. Empty until at least one replica exists. |
| port | Port the cluster accepts connections on, for the port element of a MongoDB connection string. |
| hosted_zone_id | Route53 hosted zone ID of the cluster's endpoint, for an alias record in `terraform-aws-route53-record`. |
| cluster_resource_id | AWS's own immutable ID for the cluster, used in IAM policies that name the cluster resource rather than its identifier. |
| master_user_secret | Secrets Manager secret AWS created for the primary user password, when `manage_master_user_password` is enabled. Empty otherwise. |
| instance_identifiers | Identifiers of every instance in the cluster, in creation order. The first is the initial primary. |
| instance_endpoints | Per-instance endpoints, for connecting to one specific member. |

## License

MIT — see [LICENSE.md](LICENSE.md).
