data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_kms_key" "main" {
  description             = "${var.name_prefix} main encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_main.json
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.name_prefix}-main"
  target_key_id = aws_kms_key.main.key_id
}

resource "aws_kms_key" "logs" {
  description             = "${var.name_prefix} log and audit encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_logs.json
}

resource "aws_kms_alias" "logs" {
  name          = "alias/${var.name_prefix}-logs"
  target_key_id = aws_kms_key.logs.key_id
}

data "aws_iam_policy_document" "kms_main" {
  statement {
    sid       = "EnableAccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

data "aws_iam_policy_document" "kms_logs" {
  statement {
    sid       = "EnableAccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid = "AllowLoggingServices"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]

    principals {
      type = "Service"
      identifiers = [
        "cloudtrail.amazonaws.com",
        "config.amazonaws.com",
        "logs.${data.aws_region.current.name}.amazonaws.com",
        "delivery.logs.amazonaws.com",
        "s3.amazonaws.com",
        "sns.amazonaws.com",
        "events.amazonaws.com",
        "cloudwatch.amazonaws.com",
      ]
    }
  }
}
