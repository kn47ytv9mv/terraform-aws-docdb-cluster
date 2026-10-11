variable "cluster_identifier" {
  default     = null
  description = "The identifier of the cluster: a letter first, then lowercase letters, digits and hyphens, ending alphanumerically, at most 63 characters, and unique across Amazon RDS, Neptune and DocumentDB in the account and Region. Instances are named after it with their index. If null, one is generated."

  validation {
    condition     = var.cluster_identifier == null || (can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.cluster_identifier)) && length(var.cluster_identifier) <= 63)
    error_message = "A cluster identifier must begin with a letter, contain only lowercase alphanumeric characters and single hyphens, end in an alphanumeric character, and be at most 63 characters long."
  }
}

variable "engine" {
  default     = "docdb"
  description = "The cluster engine. DocumentDB has exactly one, 'docdb'. It cannot be changed after creation."
}

variable "engine_version" {
  default     = null
  description = "The engine version (for example '5.0.0'), naming the MongoDB API level the cluster emulates. If null, AWS picks its current default, which moves between major versions, so pin it for a workload that depends on an API level."
}

variable "instance_count" {
  default     = 1
  description = "The number of instances, 0 to 16. The first is the primary and the rest are promotable replicas. Use at least 2, preferably 3 across three availability zones, to survive losing the primary. A count of 0 creates the storage with no compute."

  validation {
    condition     = var.instance_count >= 0 && var.instance_count <= 16
    error_message = "instance_count must be between 0 and 16, since a cluster supports one primary and at most 15 replicas."
  }
}

variable "instance_class" {
  default     = null
  description = "The compute and memory capacity of every instance (for example 'db.r6g.large')."
}

variable "master_username" {
  default     = null
  description = "The primary user name, 1 to 63 alphanumeric characters beginning with a letter. Changing it replaces the cluster."
}

variable "master_password" {
  default     = null
  description = "The primary user password, 8 to 100 printable ASCII characters excluding /, \" and @. It is stored in state in plain text, so prefer manage_master_user_password or master_password_wo. Mutually exclusive with both."
  sensitive   = true
}

variable "master_password_wo" {
  default     = null
  description = "The primary user password as a write-only value, never stored in state. Requires master_password_wo_version. Mutually exclusive with master_password and manage_master_user_password."
  sensitive   = true

  validation {
    condition     = length([for v in [var.master_password, var.master_password_wo, var.manage_master_user_password == true ? true : null] : v if v != null]) <= 1
    error_message = "At most one of master_password, master_password_wo, or manage_master_user_password may be set."
  }
}

variable "master_password_wo_version" {
  default     = null
  description = "The version counter for master_password_wo. Increment it to push a changed password, since Terraform cannot diff the write-only value itself."

  validation {
    condition     = (var.master_password_wo == null) == (var.master_password_wo_version == null)
    error_message = "master_password_wo and master_password_wo_version must be set together."
  }
}

variable "manage_master_user_password" {
  default     = null
  description = "Controls whether AWS generates the primary user password and rotates it in Secrets Manager. This is the recommended option. The secret always uses the AWS-managed Secrets Manager key; see Design. Mutually exclusive with master_password and master_password_wo."
}

variable "storage_encrypted" {
  default     = true
  description = "Controls whether storage is encrypted at rest. It defaults to true because encryption cannot be added to an existing cluster without a snapshot-and-restore migration."
}

variable "kms_key_id" {
  default     = null
  description = "The ARN of the KMS key encrypting storage, from terraform-aws-kms-key. Used only when storage_encrypted is true. If null, the AWS-managed RDS key is used."
}

variable "storage_type" {
  default     = null
  description = "The storage configuration, 'standard' or 'iopt1'. 'iopt1' replaces the per-I/O charge with a higher storage rate, which is cheaper for I/O-heavy workloads. If null, 'standard'."

  validation {
    condition     = var.storage_type == null || contains(["standard", "iopt1"], var.storage_type)
    error_message = "storage_type must be either 'standard' or 'iopt1'."
  }
}

variable "db_subnet_group_name" {
  default     = null
  description = "The name of the DB subnet group placing the cluster in a VPC, from terraform-aws-db-subnet-group; DocumentDB shares subnet groups with Amazon RDS. If null, the Region's default group is used."
}

variable "vpc_security_group_ids" {
  default     = null
  description = "The IDs of the security groups controlling access, from terraform-aws-vpc-security-groups. Each must allow inbound traffic on the cluster's port."
}

variable "availability_zones" {
  default     = null
  description = "The availability zones the cluster may use. DocumentDB picks three regardless and rejects an instance outside them. If null, AWS chooses."
}

variable "port" {
  default     = null
  description = "The port every instance accepts connections on. If null, 27017."
}

variable "db_cluster_parameter_group_name" {
  default     = null
  description = "The name of the cluster parameter group, from terraform-aws-docdb-cluster-parameter-group. Its family must match the major version, and it is required for audit or profiler logging. If null, AWS's default group applies."
}

variable "backup_retention_period" {
  default     = 7
  description = "The number of days automated backups are retained, 1 to 35. It defaults to 7 rather than AWS's 1."

  validation {
    condition     = var.backup_retention_period == null || (var.backup_retention_period >= 1 && var.backup_retention_period <= 35)
    error_message = "backup_retention_period must be between 1 and 35 days."
  }
}

variable "preferred_backup_window" {
  default     = null
  description = "The daily UTC window for automated backups (for example '03:00-04:00'). It must not overlap preferred_maintenance_window. If null, AWS assigns one."
}

variable "preferred_maintenance_window" {
  default     = null
  description = "The weekly UTC window for cluster maintenance (for example 'sun:05:00-sun:06:00'). If null, AWS assigns one."
}

variable "instance_preferred_maintenance_window" {
  default     = null
  description = "The weekly UTC window for instance patching, applied identically to every instance. If null, AWS assigns one per instance."
}

variable "skip_final_snapshot" {
  default     = false
  description = "Controls whether destroying the cluster skips the final snapshot. It defaults to false, which makes final_snapshot_identifier required."
}

variable "final_snapshot_identifier" {
  default     = null
  description = "The name of the snapshot taken on destroy, unique among existing snapshots. Required unless skip_final_snapshot is true."

  validation {
    condition     = var.skip_final_snapshot || var.final_snapshot_identifier != null
    error_message = "final_snapshot_identifier is required unless skip_final_snapshot is true, since a destroy would otherwise fail at teardown time rather than here."
  }
}

variable "deletion_protection" {
  default     = false
  description = "Controls whether AWS refuses to delete the cluster. Enabling it makes terraform destroy fail until a separate apply turns it off. The AWS console enables it by default, so an imported cluster may arrive with it on."
}

variable "auto_minor_version_upgrade" {
  default     = null
  description = "Controls whether minor engine upgrades are applied automatically in each instance's maintenance window. If null, they are."
}

variable "allow_major_version_upgrade" {
  default     = null
  description = "Controls whether an engine_version change across a major version is allowed; AWS rejects it otherwise. A major upgrade changes the emulated MongoDB API level."
}

variable "apply_immediately" {
  default     = null
  description = "Controls whether changes apply immediately rather than in the next maintenance window. Immediate changes can cause downtime. If null, changes are deferred."
}

variable "enabled_cloudwatch_logs_exports" {
  default     = null
  description = "The log types exported to CloudWatch Logs, of which only 'audit' and 'profiler' exist. Each also needs its parameter set in the cluster parameter group, or the log group stays empty; see Design."

  validation {
    condition     = var.enabled_cloudwatch_logs_exports == null || length(setsubtract(toset(var.enabled_cloudwatch_logs_exports), toset(["audit", "profiler"]))) == 0
    error_message = "enabled_cloudwatch_logs_exports accepts only 'audit' and 'profiler'; the RDS log types are not valid for DocumentDB."
  }
}

variable "enable_performance_insights" {
  default     = null
  description = "Controls whether Performance Insights collects load metrics on each instance. If null, it is off."
}

variable "performance_insights_kms_key_id" {
  default     = null
  description = "The ARN of the KMS key encrypting Performance Insights data. If null, the AWS-managed key is used."
}

variable "promotion_tier" {
  default     = null
  description = "The failover priority of every instance, 0 to 15; the lowest-numbered healthy replica is promoted. It is applied identically, so failover order among instances is AWS's choice."

  validation {
    condition     = var.promotion_tier == null || (var.promotion_tier >= 0 && var.promotion_tier <= 15)
    error_message = "promotion_tier must be between 0 and 15."
  }
}

variable "ca_cert_identifier" {
  default     = null
  description = "The certificate authority for each instance's TLS certificate (for example 'rds-ca-rsa2048-g1'). If null, AWS's current default."
}

variable "snapshot_identifier" {
  default     = null
  description = "The identifier or ARN of a snapshot to restore from. The cluster keeps the snapshot's engine version and encryption state."
}

variable "restore_to_point_in_time" {
  default     = null
  description = "The settings for restoring from another cluster's continuous backups. Set restore_to_time (an RFC 3339 timestamp inside the source's retention window) or use_latest_restorable_time. Changing any field replaces the cluster."
  type = object({
    source_cluster_identifier  = string
    restore_type               = optional(string)
    restore_to_time            = optional(string)
    use_latest_restorable_time = optional(bool)
  })
}

variable "global_cluster_identifier" {
  default     = null
  description = "The identifier of a DocumentDB global cluster to join. A secondary member sets neither master_username nor a password."
}

variable "tags" {
  default     = null
  description = "A map of tags to assign to the cluster and every instance in it."
}
