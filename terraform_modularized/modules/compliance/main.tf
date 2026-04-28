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

resource "aws_config_config_rule" "rds_storage_encrypted" {
  count = var.enable_aws_config ? 1 : 0
  name  = "${var.name_prefix}-rds-storage-encrypted"

  source {
    owner             = "AWS"
    source_identifier = "RDS_STORAGE_ENCRYPTED"
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}

resource "aws_config_config_rule" "s3_public_read_prohibited" {
  count = var.enable_aws_config ? 1 : 0
  name  = "${var.name_prefix}-s3-public-read-prohibited"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}
