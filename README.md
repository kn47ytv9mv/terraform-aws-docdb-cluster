# terraform-aws-docdb-cluster

Terraform module for an Amazon DocumentDB cluster and its instances.

## Cost

DocumentDB bills each instance by the second, with a ten-minute minimum,
and bills storage by the gigabyte-month. On standard storage it also
bills every million I/O requests. The I/O-optimized storage type
(`storage_type = "iopt1"`) removes that charge in exchange for a higher
storage rate, which is the cheaper choice for a busy cluster. Every
instance added through `instance_count` is charged in full at the rate
of its instance class, although all instances share a single copy of the
storage.

Backups are free up to the size of the cluster's own storage and billed
beyond it. This module keeps seven days of backups by default rather than
AWS's one, so it can reach that threshold sooner. Destroying the cluster
also leaves a final snapshot by default, and that snapshot is billed as
backup storage until someone deletes it. An engine version that has left
standard support, such as 3.6, adds an Extended Support charge for every
instance.

Several options bill in other services. Exporting logs bills CloudWatch
Logs for ingestion and storage, letting AWS manage the password bills a
Secrets Manager secret, a customer-managed KMS key bills for the key and
its requests, and Performance Insights bills once data is kept beyond its
free retention. Traffic between the cluster and clients in the same
availability zone is free, as is replication between zones, but traffic
that crosses zones or leaves the Region is billed. A cluster that joins a
global cluster also pays for its write I/O to be replicated into every
secondary Region. See
[DocumentDB pricing](https://aws.amazon.com/documentdb/pricing/) for
current rates.

## Design

Every instance in the cluster gets the same instance class, failover
priority, Performance Insights setting and maintenance window, so a
cluster whose members need to differ is outside what this module covers.

When no `cluster_identifier` is given, the module generates one from
`docdb-` and a random UUID. AWS requires the identifier to start with a
letter, and identifiers share one namespace with Amazon RDS and Neptune,
so the prefix is deliberately different from the `db-` used by
[`terraform-aws-rds-cluster`](https://github.com/kn47ytv9mv/terraform-aws-rds-cluster).

### Subnet groups

DocumentDB places its instances using an Amazon RDS subnet group, so
pass one from
[`terraform-aws-db-subnet-group`](https://github.com/kn47ytv9mv/terraform-aws-db-subnet-group).
Give that group exactly three availability zones. DocumentDB chooses
three zones when the cluster is created and refuses to place an instance
anywhere else, so any extra zones are never used.

### Passwords

There are three ways to set the primary user's password, and they are
listed here from most to least preferred. With
`manage_master_user_password`, AWS creates and rotates the password
itself and it never passes through Terraform. With `master_password_wo`
and its version counter, Terraform sends the password once and never
writes it to state. With `master_password`, the password is stored in
state as plain text.

The managed option always encrypts its secret with the AWS-managed
Secrets Manager key. If the password must be held under a key you
control, use the write-only option with a secret created by
[`terraform-aws-secretsmanager-secret`](https://github.com/kn47ytv9mv/terraform-aws-secretsmanager-secret).

### Encryption

Storage is encrypted by default, unlike the AWS CLI's default, because
encryption cannot be switched on later. An unencrypted cluster can only
be encrypted by taking a snapshot, restoring it into a new cluster and
moving traffic across. To control the key's policy and rotation, pass a
key from
[`terraform-aws-kms-key`](https://github.com/kn47ytv9mv/terraform-aws-kms-key).

### Log exports

Exporting the audit or profiler log only ships it to CloudWatch; whether
the log is written at all is decided by the cluster parameter group from
[`terraform-aws-docdb-cluster-parameter-group`](https://github.com/kn47ytv9mv/terraform-aws-docdb-cluster-parameter-group).
The audit log needs `audit_logs` turned on there, and the profiler log
needs `profiler` together with `profiler_threshold_ms` and
`profiler_sampling_rate`. Without those parameters the log group simply
stays empty, and nothing reports an error.

### Destroying the cluster

By default, destroying the cluster takes a final snapshot, which means a
`final_snapshot_identifier` must be set. AWS would only refuse at
destroy time, by which point the cluster may already be gone from the
configuration, so the module checks this at plan time instead. Deletion
protection is off by default so that `terraform destroy` works without a
separate apply to disable it first.

### MongoDB compatibility

DocumentDB emulates the MongoDB API rather than running MongoDB, and some
of the differences change how an application behaves. Check the
operations an application relies on against AWS's lists of
[supported APIs](https://docs.aws.amazon.com/documentdb/latest/developerguide/mongo-apis.html)
and
[functional differences](https://docs.aws.amazon.com/documentdb/latest/developerguide/functional-differences.html)
before migrating.

### Deliberately not covered

This module does not create Elastic clusters, which are a separate
resource with their own cost model, and it does not expose Serverless v2
scaling or the explicit member list, which `instance_count` already
governs. It can join a cluster to an existing global cluster but does not
create one. There is no option for public access, because DocumentDB
clusters are reachable only from inside their VPC, and none for IAM
database authentication, which DocumentDB does not support.

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
| cluster_identifier | Identifier of the cluster: a letter first, then lowercase letters, digits and hyphens, ending alphanumerically, at most 63 characters, and unique across Amazon RDS, Neptune and DocumentDB in the account and Region. Instances are named after it with their index. If null, one is generated. | `null` | no |
| engine | Cluster engine. DocumentDB has exactly one, `'docdb'`. Cannot be changed after creation. | `"docdb"` | no |
| engine_version | Engine version (for example `'5.0.0'`), naming the MongoDB API level the cluster emulates. If null, AWS picks its current default, which moves between major versions, so pin it for a workload that depends on an API level. | `null` | no |
| instance_count | Number of instances, 0 to 16. The first is the primary and the rest are promotable replicas. Use at least 2, preferably 3 across three availability zones, to survive losing the primary. 0 creates the storage with no compute. | `1` | no |
| instance_class | Compute and memory capacity of every instance (for example `'db.r6g.large'`). | `null` | no |
| master_username | Primary user name, 1 to 63 alphanumeric characters beginning with a letter. Changing it replaces the cluster. | `null` | no |
| master_password | Primary user password, 8 to 100 printable ASCII characters excluding /, " and @. Stored in state in plain text; prefer `manage_master_user_password` or `master_password_wo`. Mutually exclusive with both. | `null` | no |
| master_password_wo | Primary user password as a write-only value, never stored in state. Requires `master_password_wo_version`. Mutually exclusive with `master_password` and `manage_master_user_password`. | `null` | no |
| master_password_wo_version | Version counter for `master_password_wo`. Increment it to push a changed password; Terraform cannot diff the write-only value itself. | `null` | no |
| manage_master_user_password | Whether AWS generates the primary user password and rotates it in Secrets Manager. The recommended option. The secret always uses the AWS-managed Secrets Manager key; see Design. Mutually exclusive with `master_password` and `master_password_wo`. | `null` | no |
| storage_encrypted | Whether storage is encrypted at rest. Defaults true because encryption cannot be added to an existing cluster without a snapshot-and-restore migration. | `true` | no |
| kms_key_id | ARN of the KMS key encrypting storage, from `terraform-aws-kms-key`. Used only when `storage_encrypted` is true. If null, the AWS-managed RDS key is used. | `null` | no |
| storage_type | Storage configuration, `'standard'` or `'iopt1'`. `'iopt1'` replaces the per-I/O charge with a higher storage rate, which is cheaper for I/O-heavy workloads. If null, `'standard'`. | `null` | no |
| db_subnet_group_name | Name of the DB subnet group placing the cluster in a VPC, from `terraform-aws-db-subnet-group`; DocumentDB shares subnet groups with Amazon RDS. If null, the Region's default group is used. | `null` | no |
| vpc_security_group_ids | IDs of the security groups controlling access, from `terraform-aws-vpc-security-groups`. Each must allow inbound traffic on the cluster's port. | `null` | no |
| availability_zones | Availability zones the cluster may use. DocumentDB picks three regardless and rejects an instance outside them. If null, AWS chooses. | `null` | no |
| port | Port every instance accepts connections on. If null, 27017. | `null` | no |
| db_cluster_parameter_group_name | Name of the cluster parameter group, from `terraform-aws-docdb-cluster-parameter-group`. Its family must match the major version. Required for audit or profiler logging. If null, AWS's default group applies. | `null` | no |
| backup_retention_period | Days of automated backups retained, 1 to 35. Defaults to 7 rather than AWS's 1. | `7` | no |
| preferred_backup_window | Daily UTC window for automated backups (for example `'03:00-04:00'`). Must not overlap `preferred_maintenance_window`. If null, AWS assigns one. | `null` | no |
| preferred_maintenance_window | Weekly UTC window for cluster maintenance (for example `'sun:05:00-sun:06:00'`). If null, AWS assigns one. | `null` | no |
| instance_preferred_maintenance_window | Weekly UTC window for instance patching, applied identically to every instance. If null, AWS assigns one per instance. | `null` | no |
| skip_final_snapshot | Whether destroying the cluster skips the final snapshot. Defaults false, which makes `final_snapshot_identifier` required. | `false` | no |
| final_snapshot_identifier | Name of the snapshot taken on destroy, unique among existing snapshots. Required unless `skip_final_snapshot` is true. | `null` | no |
| deletion_protection | Whether AWS refuses to delete the cluster. Enabling it makes terraform destroy fail until a separate apply turns it off. The AWS console enables it by default, so an imported cluster may arrive with it on. | `false` | no |
| auto_minor_version_upgrade | Whether minor engine upgrades are applied automatically in each instance's maintenance window. If null, enabled. | `null` | no |
| allow_major_version_upgrade | Whether an `engine_version` change across a major version is allowed; AWS rejects it otherwise. A major upgrade changes the emulated MongoDB API level. | `null` | no |
| apply_immediately | Whether changes apply immediately rather than in the next maintenance window. Immediate changes can cause downtime. If null, changes are deferred. | `null` | no |
| enabled_cloudwatch_logs_exports | Log types exported to CloudWatch Logs: only `'audit'` and `'profiler'`. Each also needs its parameter set in the cluster parameter group, or the log group stays empty; see Design. | `null` | no |
| enable_performance_insights | Whether Performance Insights collects load metrics on each instance. If null, disabled. | `null` | no |
| performance_insights_kms_key_id | ARN of the KMS key encrypting Performance Insights data. If null, the AWS-managed key is used. | `null` | no |
| promotion_tier | Failover priority of every instance, 0 to 15; the lowest-numbered healthy replica is promoted. Applied identically, so failover order among instances is AWS's choice. | `null` | no |
| ca_cert_identifier | Certificate authority for each instance's TLS certificate (for example `'rds-ca-rsa2048-g1'`). If null, AWS's current default. | `null` | no |
| snapshot_identifier | Identifier or ARN of a snapshot to restore from. The cluster keeps the snapshot's engine version and encryption state. | `null` | no |
| restore_to_point_in_time | Restore from another cluster's continuous backups. Set `restore_to_time` (an RFC 3339 timestamp inside the source's retention window) or `use_latest_restorable_time`. Changing any field replaces the cluster. | `null` | no |
| global_cluster_identifier | Identifier of a DocumentDB global cluster to join. A secondary member sets neither `master_username` nor a password. | `null` | no |
| tags | A map of tags to assign to the cluster and every instance in it. | `null` | no |

## Outputs

| Name | Description |
|---|---|
| id | The ID of the cluster. |
| arn | The ARN of the cluster, in the RDS ARN namespace (arn:aws:rds:...:cluster/...). |
| cluster_identifier | The identifier of the cluster. |
| endpoint | Primary endpoint. Point a MongoDB driver here; it follows the primary across a failover. |
| reader_endpoint | Reader endpoint, balancing across replicas. Use with read preference secondaryPreferred. Empty until a replica exists. |
| port | Port the cluster accepts connections on. |
| hosted_zone_id | Route 53 hosted zone ID of the endpoint, for an alias record in `terraform-aws-route53-record`. |
| cluster_resource_id | Immutable resource ID of the cluster, used in IAM policies that name the cluster resource. |
| master_user_secret | Secrets Manager secret AWS created for the primary user password when `manage_master_user_password` is enabled. Empty otherwise. |
| instance_identifiers | Identifiers of every instance in the cluster, in creation order. The first is the initial primary. |
| instance_endpoints | Per-instance endpoints, for connecting to one specific member. |

## License

MIT — see [LICENSE.md](LICENSE.md).
