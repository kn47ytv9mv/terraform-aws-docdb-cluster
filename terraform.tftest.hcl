mock_provider "aws" {}

run "invalid_cluster_identifier_is_rejected" {
  command = plan

  variables {
    cluster_identifier  = "0Bad_Cluster"
    instance_class      = "db.r6g.large"
    skip_final_snapshot = true
  }

  expect_failures = [var.cluster_identifier]
}

run "instance_count_above_the_cluster_limit_is_rejected" {
  command = plan

  variables {
    instance_class      = "db.r6g.large"
    skip_final_snapshot = true
    instance_count      = 17
  }

  expect_failures = [var.instance_count]
}

run "master_password_and_managed_password_are_mutually_exclusive" {
  command = plan

  variables {
    instance_class              = "db.r6g.large"
    skip_final_snapshot         = true
    master_password             = "correct-horse-battery"
    manage_master_user_password = true
  }

  expect_failures = [var.master_password_wo]
}

run "master_password_wo_requires_its_version" {
  command = plan

  variables {
    instance_class      = "db.r6g.large"
    skip_final_snapshot = true
    master_password_wo  = "correct-horse-battery"
  }

  expect_failures = [var.master_password_wo_version]
}

run "unknown_storage_type_is_rejected" {
  command = plan

  variables {
    instance_class      = "db.r6g.large"
    skip_final_snapshot = true
    storage_type        = "gp3"
  }

  expect_failures = [var.storage_type]
}

run "backup_retention_period_beyond_the_maximum_is_rejected" {
  command = plan

  variables {
    instance_class          = "db.r6g.large"
    skip_final_snapshot     = true
    backup_retention_period = 36
  }

  expect_failures = [var.backup_retention_period]
}

run "final_snapshot_identifier_required_unless_skipped" {
  command = plan

  variables {
    instance_class = "db.r6g.large"
  }

  expect_failures = [var.final_snapshot_identifier]
}

run "rds_log_types_are_rejected" {
  command = plan

  variables {
    instance_class                  = "db.r6g.large"
    skip_final_snapshot             = true
    enabled_cloudwatch_logs_exports = ["error", "slowquery"]
  }

  expect_failures = [var.enabled_cloudwatch_logs_exports]
}

run "promotion_tier_beyond_the_maximum_is_rejected" {
  command = plan

  variables {
    instance_class      = "db.r6g.large"
    skip_final_snapshot = true
    promotion_tier      = 16
  }

  expect_failures = [var.promotion_tier]
}

run "cluster_identifier_defaults_to_prefixed_random_uuid" {
  command = apply

  variables {
    instance_class      = "db.r6g.large"
    skip_final_snapshot = true
  }

  assert {
    condition     = aws_docdb_cluster.resource.cluster_identifier == "docdb-${random_uuid.resource.id}"
    error_message = "Leaving cluster_identifier unset should fall back to a letter-prefixed random_uuid, since AWS rejects an identifier that does not begin with a letter."
  }
}

run "one_instance_by_default" {
  command = plan

  variables {
    instance_class      = "db.r6g.large"
    skip_final_snapshot = true
  }

  assert {
    condition     = length(aws_docdb_cluster_instance.resource) == 1
    error_message = "instance_count should default to a single primary instance."
  }
}

run "instance_count_creates_that_many_instances" {
  command = apply

  variables {
    cluster_identifier  = "my-cluster"
    instance_class      = "db.r6g.large"
    skip_final_snapshot = true
    instance_count      = 3
  }

  assert {
    condition     = length(aws_docdb_cluster_instance.resource) == 3
    error_message = "Each instance_count should produce one cluster instance."
  }

  assert {
    condition     = aws_docdb_cluster_instance.resource[0].identifier == "my-cluster-0"
    error_message = "Each instance should be named after the cluster, suffixed with its index."
  }

  assert {
    condition     = aws_docdb_cluster_instance.resource[2].identifier == "my-cluster-2"
    error_message = "The last instance's index should match its position in the count."
  }
}

run "zero_instances_creates_a_cluster_with_none" {
  command = plan

  variables {
    skip_final_snapshot = true
    instance_count      = 0
  }

  assert {
    condition     = length(aws_docdb_cluster_instance.resource) == 0
    error_message = "instance_count of 0 should create the cluster volume with no compute attached."
  }
}

run "secure_defaults_are_applied" {
  command = plan

  variables {
    instance_class      = "db.r6g.large"
    skip_final_snapshot = true
  }

  assert {
    condition     = aws_docdb_cluster.resource.storage_encrypted == true
    error_message = "Cluster storage encryption should be enabled by default, since it cannot be turned on for an existing cluster."
  }

  assert {
    condition     = aws_docdb_cluster.resource.backup_retention_period == 7
    error_message = "Automated backups should be retained for 7 days by default."
  }

  assert {
    condition     = aws_docdb_cluster.resource.engine == "docdb"
    error_message = "The engine should default to DocumentDB's only engine."
  }
}

run "documentdb_log_types_pass_through" {
  command = plan

  variables {
    instance_class                  = "db.r6g.large"
    skip_final_snapshot             = true
    enabled_cloudwatch_logs_exports = ["audit", "profiler"]
  }

  assert {
    condition     = length(aws_docdb_cluster.resource.enabled_cloudwatch_logs_exports) == 2
    error_message = "Both DocumentDB log types should reach the cluster."
  }
}

run "no_restore_block_by_default" {
  command = plan

  variables {
    instance_class      = "db.r6g.large"
    skip_final_snapshot = true
  }

  assert {
    condition     = length(aws_docdb_cluster.resource.restore_to_point_in_time) == 0
    error_message = "Leaving restore_to_point_in_time unset should emit no restore block."
  }
}

run "restore_to_point_in_time_creates_one_block" {
  command = plan

  variables {
    instance_class      = "db.r6g.large"
    skip_final_snapshot = true
    restore_to_point_in_time = {
      source_cluster_identifier  = "source-cluster"
      use_latest_restorable_time = true
    }
  }

  assert {
    condition     = length(aws_docdb_cluster.resource.restore_to_point_in_time) == 1
    error_message = "Setting restore_to_point_in_time should emit exactly one restore block."
  }

  assert {
    condition     = aws_docdb_cluster.resource.restore_to_point_in_time[0].source_cluster_identifier == "source-cluster"
    error_message = "The restore block's source cluster should pass through unchanged."
  }
}

run "readme_default_example" {
  command = plan

  variables {
    engine_version                  = "5.0.0"
    instance_class                  = "db.r6g.large"
    instance_count                  = 3
    master_username                 = "app"
    manage_master_user_password     = true
    db_subnet_group_name            = "production-database"
    vpc_security_group_ids          = ["sg-1111"]
    db_cluster_parameter_group_name = "production-docdb"
    enabled_cloudwatch_logs_exports = ["audit", "profiler"]
    final_snapshot_identifier       = "app-final"
  }
}

run "readme_github_source_example" {
  command = plan

  variables {
    cluster_identifier          = "analytics"
    instance_class              = "db.t4g.medium"
    master_username             = "app"
    manage_master_user_password = true
    storage_type                = "iopt1"
    backup_retention_period     = 14
    skip_final_snapshot         = true
  }
}
