data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.name_prefix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_iam_policy_document" "lambda_app" {
  statement {
    sid = "KmsUse"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = [
      aws_kms_key.app.arn,
      aws_kms_key.audit.arn,
    ]
  }

  statement {
    sid = "EventQueueAccess"
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [
      aws_sqs_queue.events.arn,
      aws_sqs_queue.events_dlq.arn,
    ]
  }

  statement {
    sid = "AuditEvidenceWrite"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.audit_worm.arn,
      "${aws_s3_bucket.audit_worm.arn}/*",
    ]
  }

  statement {
    sid       = "AlertsPublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_iam_policy" "lambda_app" {
  name   = "${local.name_prefix}-lambda-app-policy"
  policy = data.aws_iam_policy_document.lambda_app.json
}

resource "aws_iam_role_policy_attachment" "lambda_app" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda_app.arn
}

data "aws_iam_policy_document" "auditor_readonly" {
  statement {
    sid = "AuditReadOnly"
    actions = [
      "cloudtrail:LookupEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:GetLogEvents",
      "s3:GetObject",
      "s3:ListBucket",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "auditor_readonly" {
  name        = "${local.name_prefix}-auditor-readonly"
  description = "Read-only policy for regulatory auditors."
  policy      = data.aws_iam_policy_document.auditor_readonly.json
}
