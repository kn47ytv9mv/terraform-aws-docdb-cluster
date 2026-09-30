variable "cluster_identifier" {
  default     = null
  description = "Identifier of the cluster. Must begin with a letter, contain only lowercase alphanumeric characters and hyphens, end in an alphanumeric character, and run no longer than 63 characters — AWS rejects anything else, and the name must be unique across Amazon RDS, Amazon Neptune, and Amazon DocumentDB in the account and Region. If null, a unique identifier is generated. Each cluster instance is named after it, suffixed with its index."

  validation {
    condition     = var.cluster_identifier == null || (can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.cluster_identifier)) && length(var.cluster_identifier) <= 63)
    error_message = "A cluster identifier must begin with a letter, contain only lowercase alphanumeric characters and single hyphens, end in an alphanumeric character, and be at most 63 characters long."
  }
}

variable "engine" {
  default     = "docdb"
  description = "Cluster engine. Amazon DocumentDB has exactly one, 'docdb'; the argument exists because this resource shares the RDS control plane. Cannot be changed after creation."
}

variable "engine_version" {
  default     = null
  description = "Engine version (for example '5.0.0' or '8.0.0'), naming the MongoDB API version the cluster emulates. If null, AWS picks its own current default, which moves when AWS releases a new major version — pin it for any workload that depends on a particular API level."
}

variable "instance_count" {
  default     = 1
  description = "Number of instances in the cluster, 0 to 16. The first is the primary; every other is a replica that serves reads and can be promoted on failover. Defaults to 1, which is a single primary and no failover target — raise it to at least 2, and preferably 3 across three availability zones, for a cluster that must survive losing its primary without downtime. Setting it to 0 creates the cluster volume with no compute attached, which is the shape AWS's own CLI produces."

  validation {
    condition     = var.instance_count >= 0 && var.instance_count <= 16
    error_message = "instance_count must be between 0 and 16, since a cluster supports one primary and at most 15 replicas."
  }
}

variable "instance_class" {
  default     = null
  description = "Compute and memory capacity of each cluster instance (for example 'db.r6g.large'). Applied identically to every instance this module creates."
}

variable "master_username" {
  default     = null
  description = "Primary user name, 1 to 63 alphanumeric characters beginning with a letter. Cannot be changed after creation without replacing the cluster."
}

variable "master_password" {
  default     = null
  description = "Primary user password, 8 to 100 printable ASCII characters excluding the forward slash, double quotation mark, and at sign. Stored in Terraform state in plain text. Prefer manage_master_user_password (AWS generates and rotates the password in Secrets Manager) or master_password_wo (never written to state at all). Mutually exclusive with both."
  sensitive   = true
}

variable "master_password_wo" {
  default     = null
  description = "Primary user password as a write-only value — sent to AWS during apply but never persisted to Terraform state. Requires master_password_wo_version. Mutually exclusive with master_password and manage_master_user_password."
  sensitive   = true

  validation {
    condition     = length([for v in [var.master_password, var.master_password_wo, var.manage_master_user_password == true ? true : null] : v if v != null]) <= 1
    error_message = "At most one of master_password, master_password_wo, or manage_master_user_password may be set."
  }
}

variable "master_password_wo_version" {
  default     = null
  description = "Version counter for master_password_wo. Increment it to push a changed password; leaving it unchanged leaves the password alone, since Terraform cannot see the write-only value itself to diff it."

  validation {
    condition     = (var.master_password_wo == null) == (var.master_password_wo_version == null)
    error_message = "master_password_wo and master_password_wo_version must be set together."
  }
}

variable "manage_master_user_password" {
  default     = null
  description = "Whether AWS generates the primary user password and manages it in Secrets Manager, including rotation. The recommended option — no password ever passes through Terraform. The secret is encrypted with the account's AWS-managed key for Secrets Manager; this provider version offers no argument for pointing it at a customer-managed key, so a cluster that needs one has to be created without this option. Mutually exclusive with master_password and master_password_wo. If null, AWS's own default (disabled) applies."
}

variable "storage_encrypted" {
  default     = true
  description = "Whether cluster storage is encrypted at rest. Defaults true because encryption cannot be turned on for an existing cluster — an unencrypted cluster has to be snapshotted and restored into a new encrypted one, which is a migration rather than a setting change."
}

variable "kms_key_id" {
  default     = null
  description = "ARN of the KMS key encrypting cluster storage, from terraform-aws-kms-key. Only used when storage_encrypted is true. If null, AWS's own managed key for RDS is used."
}

variable "storage_type" {
  default     = null
  description = "Cluster storage configuration, 'standard' or 'iopt1'. Standard bills storage and I/O separately; I/O-optimized bills a higher storage rate and no I/O charge, which is cheaper once I/O exceeds roughly a quarter of the bill. If null, AWS's own default ('standard') applies."

  validation {
    condition     = var.storage_type == null || contains(["standard", "iopt1"], var.storage_type)
    error_message = "storage_type must be either 'standard' or 'iopt1'."
  }
}

variable "db_subnet_group_name" {
  default     = null
  description = "Name of the subnet group placing this cluster in a VPC, from terraform-aws-db-subnet-group. DocumentDB shares DB subnet groups with Amazon RDS, so no DocumentDB-specific module is needed. If null, AWS uses the Region's default subnet group, which is rarely the intent."
}

variable "vpc_security_group_ids" {
  default     = null
  description = "IDs of the security groups controlling network access to the cluster, from terraform-aws-vpc-security-groups. Each must permit inbound traffic on the cluster's port, or nothing can connect."
}

variable "availability_zones" {
  default     = null
  description = "Availability zones the cluster may place instances in. DocumentDB selects three regardless of how many are supplied, and rejects an instance placed in a zone outside that chosen set. If null, AWS chooses."
}

variable "port" {
  default     = null
  description = "Port the cluster accepts connections on. Every instance in the cluster uses the same port. If null, DocumentDB's own default (27017) applies."
}

variable "db_cluster_parameter_group_name" {
  default     = null
  description = "Name of the cluster parameter group applying engine configuration, from terraform-aws-docdb-cluster-parameter-group. Its family must match this cluster's major version. Required to turn on audit or profiler logging, since both are parameters rather than cluster arguments. If null, AWS's default group applies."
}

variable "backup_retention_period" {
  default     = 7
  description = "Days of automated backups retained, 1 to 35. Defaults to 7 rather than AWS's own default of 1, matching this family's direction elsewhere of enabling durability protections out of the box."

  validation {
    condition     = var.backup_retention_period == null || (var.backup_retention_period >= 1 && var.backup_retention_period <= 35)
    error_message = "backup_retention_period must be between 1 and 35 days."
  }
}

variable "preferred_backup_window" {
  default     = null
  description = "Daily UTC window automated backups are taken in (for example '03:00-04:00'). Must not overlap preferred_maintenance_window. If null, AWS assigns one."
}

variable "preferred_maintenance_window" {
  default     = null
  description = "Weekly UTC window AWS applies cluster maintenance in (for example 'sun:05:00-sun:06:00'). If null, AWS assigns one."
}

variable "instance_preferred_maintenance_window" {
  default     = null
  description = "Weekly UTC window AWS patches each instance in, separate from the cluster window and applied identically to every instance this module creates. Staggering it across a cluster's members is past what this module covers. If null, AWS assigns one per instance."
}

variable "skip_final_snapshot" {
  default     = false
  description = "Whether destroying the cluster skips taking a final snapshot. Defaults false, so data is not lost to a single destroy — which means final_snapshot_identifier must be set."
}

variable "final_snapshot_identifier" {
  default     = null
  description = "Name of the snapshot taken when the cluster is destroyed. Required unless skip_final_snapshot is true. Must be unique among existing snapshots."

  validation {
    condition     = var.skip_final_snapshot || var.final_snapshot_identifier != null
    error_message = "final_snapshot_identifier is required unless skip_final_snapshot is true, since a destroy would otherwise fail at teardown time rather than here."
  }
}

variable "deletion_protection" {
  default     = false
  description = "Whether AWS refuses to delete the cluster while set. Defaults false, since enabling it makes terraform destroy fail until a separate apply turns it off again. Note that AWS's own console enables it by default, so a cluster created there and imported will arrive with it on."
}

variable "auto_minor_version_upgrade" {
  default     = null
  description = "Whether AWS applies minor engine version upgrades to each instance automatically during its maintenance window. If null, AWS's own default (enabled) applies."
}

variable "allow_major_version_upgrade" {
  default     = null
  description = "Whether a change to engine_version crossing a major version is permitted. Without it, AWS rejects the upgrade rather than performing it. A major upgrade changes the MongoDB API version the cluster emulates, so verify the application against the new level first."
}

variable "apply_immediately" {
  default     = null
  description = "Whether modifications are applied immediately rather than deferred to the next maintenance window. Immediate application can cause downtime. If null, AWS's own default (defer) applies."
}

variable "enabled_cloudwatch_logs_exports" {
  default     = null
  description = "Log types exported to CloudWatch Logs. DocumentDB supports exactly two, 'audit' and 'profiler' — these are not the RDS log types. Each also requires the matching parameter in db_cluster_parameter_group_name: 'audit' needs audit_logs enabled, and 'profiler' needs profiler enabled together with profiler_threshold_ms and profiler_sampling_rate. If null, no logs are exported."

  validation {
    condition     = var.enabled_cloudwatch_logs_exports == null || length(setsubtract(toset(var.enabled_cloudwatch_logs_exports), toset(["audit", "profiler"]))) == 0
    error_message = "enabled_cloudwatch_logs_exports accepts only 'audit' and 'profiler'; the RDS log types are not valid for DocumentDB."
  }
}

variable "enable_performance_insights" {
  default     = null
  description = "Whether Performance Insights collects database load metrics on each instance. If null, AWS's own default (disabled) applies."
}

variable "performance_insights_kms_key_id" {
  default     = null
  description = "ARN of the KMS key encrypting Performance Insights data. If null, AWS's own managed key is used."
}

variable "promotion_tier" {
  default     = null
  description = "Failover priority of each instance, 0 to 15. DocumentDB promotes the lowest-numbered healthy replica when the primary fails. Applied identically to every instance this module creates, so failover order among them is AWS's choice."

  validation {
    condition     = var.promotion_tier == null || (var.promotion_tier >= 0 && var.promotion_tier <= 15)
    error_message = "promotion_tier must be between 0 and 15."
  }
}

variable "ca_cert_identifier" {
  default     = null
  description = "Certificate authority bundle used for each instance's TLS certificate (for example 'rds-ca-rsa2048-g1'). If null, AWS's own current default applies."
}

variable "snapshot_identifier" {
  default     = null
  description = "Identifier or ARN of a snapshot to restore this cluster from, instead of creating an empty one. The restored cluster keeps the snapshot's engine version and encryption state."
}

variable "restore_to_point_in_time" {
  default     = null
  description = "Restore this cluster from another cluster's continuous backups instead of creating an empty one. Set either restore_to_time, an RFC 3339 timestamp inside the source cluster's backup retention window, or use_latest_restorable_time. Changing any field replaces the cluster."
  type = object({
    source_cluster_identifier  = string
    restore_type               = optional(string)
    restore_to_time            = optional(string)
    use_latest_restorable_time = optional(bool)
  })
}

variable "global_cluster_identifier" {
  default     = null
  description = "Identifier of a DocumentDB global cluster to join this cluster to, making it a member of a cross-region global cluster. A secondary member sets neither master_username nor a password: the primary owns them."
}

variable "tags" {
  default     = null
  description = "A map of tags to assign to the cluster and every instance in it."
}
