resource "aws_guardduty_detector" "main" {
  count  = var.enable_guardduty ? 1 : 0
  enable = true
}

resource "aws_securityhub_account" "main" {
  count = var.enable_securityhub ? 1 : 0
}

resource "aws_securityhub_standards_subscription" "foundational" {
  count         = var.enable_securityhub ? 1 : 0
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.main]
}

resource "aws_iam_role" "config" {
  count = var.enable_aws_config ? 1 : 0
  name  = "${var.name_prefix}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "config.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  count      = var.enable_aws_config ? 1 : 0
  role       = aws_iam_role.config[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_configuration_recorder" "main" {
  count    = var.enable_aws_config ? 1 : 0
  name     = "${var.name_prefix}-recorder"
  role_arn = aws_iam_role.config[0].arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  count          = var.enable_aws_config ? 1 : 0
  name           = "${var.name_prefix}-delivery"
  s3_bucket_name = var.central_logs_bucket
  s3_key_prefix  = "Config"
  s3_kms_key_arn = var.logs_kms_key_arn

}

resource "aws_config_configuration_recorder_status" "main" {
  count      = var.enable_aws_config ? 1 : 0
  name       = aws_config_configuration_recorder.main[0].name
  is_enabled = true
  depends_on = [
    aws_config_delivery_channel.main,
    aws_iam_role_policy_attachment.config,
  ]
}

locals {
  aws_config_managed_rules = {
    s3_bucket_sse_enabled = {
      name              = "s3-bucket-sse-enabled"
      source_identifier = "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
    }
    s3_public_read_prohibited = {
      name              = "s3-public-read-prohibited"
      source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
    }
    s3_public_write_prohibited = {
      name              = "s3-public-write-prohibited"
      source_identifier = "S3_BUCKET_PUBLIC_WRITE_PROHIBITED"
    }
    s3_bucket_level_public_access_prohibited = {
      name              = "s3-bucket-level-public-access-prohibited"
      source_identifier = "S3_BUCKET_LEVEL_PUBLIC_ACCESS_PROHIBITED"
    }
    s3_account_level_public_access_blocks = {
      name              = "s3-account-level-public-access-blocks"
      source_identifier = "S3_ACCOUNT_LEVEL_PUBLIC_ACCESS_BLOCKS"
    }
    s3_bucket_versioning_enabled = {
      name              = "s3-bucket-versioning-enabled"
      source_identifier = "S3_BUCKET_VERSIONING_ENABLED"
    }
    s3_bucket_default_lock_enabled = {
      name              = "s3-bucket-default-lock-enabled"
      source_identifier = "S3_BUCKET_DEFAULT_LOCK_ENABLED"
    }
    rds_storage_encrypted = {
      name              = "rds-storage-encrypted"
      source_identifier = "RDS_STORAGE_ENCRYPTED"
    }
    rds_instance_public_access_check = {
      name              = "rds-instance-public-access-check"
      source_identifier = "RDS_INSTANCE_PUBLIC_ACCESS_CHECK"
    }
    rds_snapshots_public_prohibited = {
      name              = "rds-snapshots-public-prohibited"
      source_identifier = "RDS_SNAPSHOTS_PUBLIC_PROHIBITED"
    }
    rds_snapshot_encrypted = {
      name              = "rds-snapshot-encrypted"
      source_identifier = "RDS_SNAPSHOT_ENCRYPTED"
    }
    db_instance_backup_enabled = {
      name              = "db-instance-backup-enabled"
      source_identifier = "DB_INSTANCE_BACKUP_ENABLED"
      input_parameters = {
        backupRetentionMinimum = "1"
      }
    }
    encrypted_volumes = {
      name              = "encrypted-volumes"
      source_identifier = "ENCRYPTED_VOLUMES"
    }
    ec2_ebs_encryption_by_default = {
      name              = "ec2-ebs-encryption-by-default"
      source_identifier = "EC2_EBS_ENCRYPTION_BY_DEFAULT"
    }
    cloud_trail_enabled = {
      name              = "cloud-trail-enabled"
      source_identifier = "CLOUD_TRAIL_ENABLED"
    }
    cloud_trail_encryption_enabled = {
      name              = "cloud-trail-encryption-enabled"
      source_identifier = "CLOUD_TRAIL_ENCRYPTION_ENABLED"
    }
    cloud_trail_log_file_validation_enabled = {
      name              = "cloud-trail-log-file-validation-enabled"
      source_identifier = "CLOUD_TRAIL_LOG_FILE_VALIDATION_ENABLED"
    }
  }
}

resource "aws_config_config_rule" "managed" {
  for_each = {
    for rule_key, rule in local.aws_config_managed_rules : rule_key => rule
    if var.enable_aws_config
  }

  name = "${var.name_prefix}-${each.value.name}"

  source {
    owner             = "AWS"
    source_identifier = each.value.source_identifier
  }

  input_parameters = try(each.value.input_parameters, null) != null ? jsonencode(each.value.input_parameters) : null

  depends_on = [aws_config_configuration_recorder_status.main]
}
