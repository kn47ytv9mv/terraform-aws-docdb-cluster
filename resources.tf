locals {
  cluster_identifier = coalesce(var.cluster_identifier, "docdb-${random_uuid.resource.id}")
}

resource "random_uuid" "resource" {}

resource "aws_docdb_cluster" "resource" {
  cluster_identifier = local.cluster_identifier
  engine             = var.engine
  engine_version     = var.engine_version

  master_username = var.master_username

  master_password             = var.master_password
  master_password_wo          = var.master_password_wo
  master_password_wo_version  = var.master_password_wo_version
  manage_master_user_password = var.manage_master_user_password

  storage_encrypted = var.storage_encrypted
  kms_key_id        = var.kms_key_id
  storage_type      = var.storage_type

  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = var.vpc_security_group_ids
  availability_zones     = var.availability_zones
  port                   = var.port

  db_cluster_parameter_group_name = var.db_cluster_parameter_group_name

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.final_snapshot_identifier
  deletion_protection       = var.deletion_protection

  allow_major_version_upgrade = var.allow_major_version_upgrade
  apply_immediately           = var.apply_immediately

  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  snapshot_identifier       = var.snapshot_identifier
  global_cluster_identifier = var.global_cluster_identifier

  dynamic "restore_to_point_in_time" {
    for_each = var.restore_to_point_in_time[*]

    content {
      source_cluster_identifier  = restore_to_point_in_time.value.source_cluster_identifier
      restore_type               = restore_to_point_in_time.value.restore_type
      restore_to_time            = restore_to_point_in_time.value.restore_to_time
      use_latest_restorable_time = restore_to_point_in_time.value.use_latest_restorable_time
    }
  }

  tags = var.tags
}

resource "aws_docdb_cluster_instance" "resource" {
  count = var.instance_count

  identifier         = "${local.cluster_identifier}-${count.index}"
  cluster_identifier = aws_docdb_cluster.resource.id
  engine             = aws_docdb_cluster.resource.engine
  instance_class     = var.instance_class

  promotion_tier = var.promotion_tier

  enable_performance_insights     = var.enable_performance_insights
  performance_insights_kms_key_id = var.performance_insights_kms_key_id

  auto_minor_version_upgrade   = var.auto_minor_version_upgrade
  apply_immediately            = var.apply_immediately
  preferred_maintenance_window = var.instance_preferred_maintenance_window
  ca_cert_identifier           = var.ca_cert_identifier

  tags = var.tags
}

output "id" {
  description = "The ID of the cluster."
  value       = aws_docdb_cluster.resource.id
}

output "arn" {
  description = "The ARN of the cluster. DocumentDB clusters live in the RDS ARN namespace, so this reads arn:aws:rds:...:cluster/..."
  value       = aws_docdb_cluster.resource.arn
}

output "cluster_identifier" {
  description = "The identifier of the cluster."
  value       = aws_docdb_cluster.resource.cluster_identifier
}

output "endpoint" {
  description = "Primary endpoint of the cluster. Point a MongoDB driver here — it follows the current primary across a failover, so writes never need to be re-addressed."
  value       = aws_docdb_cluster.resource.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint of the cluster, load-balancing connections across its replicas. Use it with a read preference of secondaryPreferred. Empty until at least one replica exists."
  value       = aws_docdb_cluster.resource.reader_endpoint
}

output "port" {
  description = "Port the cluster accepts connections on, for the port element of a MongoDB connection string."
  value       = aws_docdb_cluster.resource.port
}

output "hosted_zone_id" {
  description = "Route53 hosted zone ID of the cluster's endpoint, for an alias record in terraform-aws-route53-record."
  value       = aws_docdb_cluster.resource.hosted_zone_id
}

output "cluster_resource_id" {
  description = "AWS's own immutable ID for the cluster, used in IAM policies that name the cluster resource rather than its identifier."
  value       = aws_docdb_cluster.resource.cluster_resource_id
}

output "master_user_secret" {
  description = "Secrets Manager secret AWS created for the primary user password, when manage_master_user_password is enabled. Empty otherwise."
  value       = aws_docdb_cluster.resource.master_user_secret
}

output "instance_identifiers" {
  description = "Identifiers of every instance in the cluster, in creation order. The first is the initial primary."
  value       = aws_docdb_cluster_instance.resource[*].identifier
}

output "instance_endpoints" {
  description = "Per-instance endpoints, for connecting to one specific member rather than through the cluster's primary or reader endpoint."
  value       = aws_docdb_cluster_instance.resource[*].endpoint
}
