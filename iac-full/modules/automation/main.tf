resource "aws_sns_topic" "alerts" {
  name              = "${var.name_prefix}-alerts"
  kms_master_key_id = var.logs_kms_key_arn
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

data "aws_caller_identity" "current" {}

resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountTopicAdministration"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "sns:GetTopicAttributes",
          "sns:SetTopicAttributes",
          "sns:AddPermission",
          "sns:RemovePermission",
          "sns:DeleteTopic",
          "sns:Subscribe",
          "sns:ListSubscriptionsByTopic",
          "sns:Publish"
        ]
        Resource = aws_sns_topic.alerts.arn
      },
      {
        Sid    = "AllowMonitoringServicesPublish"
        Effect = "Allow"
        Principal = {
          Service = [
            "events.amazonaws.com",
            "cloudwatch.amazonaws.com"
          ]
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

locals {
  security_monitoring_event_rules = {
    root_account_activity = {
      description = "Alert when the AWS root account is used."
      event_pattern = jsonencode({
        "detail-type" = [
          "AWS API Call via CloudTrail",
          "AWS Console Sign In via CloudTrail"
        ]
        detail = {
          userIdentity = {
            type = ["Root"]
          }
        }
      })
    }

    console_login_failure = {
      description = "Alert on failed AWS console login attempts."
      event_pattern = jsonencode({
        source        = ["aws.signin"]
        "detail-type" = ["AWS Console Sign In via CloudTrail"]
        detail = {
          eventName = ["ConsoleLogin"]
          responseElements = {
            ConsoleLogin = ["Failure"]
          }
        }
      })
    }

    unauthorized_api_call = {
      description = "Alert on access denied and unauthorized API activity."
      event_pattern = jsonencode({
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          errorCode = [
            { prefix = "AccessDenied" },
            { prefix = "UnauthorizedOperation" }
          ]
        }
      })
    }

    cloudtrail_tampering = {
      description = "Alert when CloudTrail logging or event selectors are changed."
      event_pattern = jsonencode({
        source        = ["aws.cloudtrail"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          eventSource = ["cloudtrail.amazonaws.com"]
          eventName = [
            "DeleteTrail",
            "StopLogging",
            "UpdateTrail",
            "PutEventSelectors"
          ]
        }
      })
    }

    iam_policy_change = {
      description = "Alert on IAM identity, role, access key, and policy changes."
      event_pattern = jsonencode({
        source        = ["aws.iam"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          eventSource = ["iam.amazonaws.com"]
          eventName = [
            "AttachRolePolicy",
            "AttachUserPolicy",
            "CreateAccessKey",
            "CreatePolicy",
            "CreatePolicyVersion",
            "CreateRole",
            "CreateUser",
            "DeleteAccessKey",
            "DeletePolicy",
            "DeletePolicyVersion",
            "DeleteRole",
            "DeleteUser",
            "DetachRolePolicy",
            "DetachUserPolicy",
            "PutRolePolicy",
            "PutUserPolicy",
            "UpdateAssumeRolePolicy"
          ]
        }
      })
    }

    security_group_change = {
      description = "Alert on Security Group rule and boundary changes."
      event_pattern = jsonencode({
        source        = ["aws.ec2"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          eventSource = ["ec2.amazonaws.com"]
          eventName = [
            "AuthorizeSecurityGroupIngress",
            "AuthorizeSecurityGroupEgress",
            "CreateSecurityGroup",
            "DeleteSecurityGroup",
            "ModifySecurityGroupRules",
            "RevokeSecurityGroupIngress",
            "RevokeSecurityGroupEgress",
            "UpdateSecurityGroupRuleDescriptionsIngress"
          ]
        }
      })
    }

    s3_public_access_change = {
      description = "Alert on S3 public access control and bucket policy changes."
      event_pattern = jsonencode({
        source        = ["aws.s3"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          eventSource = ["s3.amazonaws.com"]
          eventName = [
            "DeleteBucketPolicy",
            "DeleteBucketPublicAccessBlock",
            "PutBucketAcl",
            "PutBucketPolicy",
            "PutBucketPublicAccessBlock"
          ]
        }
      })
    }
  }
}

data "archive_file" "audit_report" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/audit_report.js"
  output_path = "${path.module}/.terraform-build/audit_report.zip"
}

resource "aws_iam_role" "audit_report_lambda" {
  name = "${var.name_prefix}-audit-report-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "audit_report_basic" {
  role       = aws_iam_role.audit_report_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "audit_report" {
  name = "${var.name_prefix}-audit-report-policy"
  role = aws_iam_role.audit_report_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish",
          "securityhub:GetFindings",
          "guardduty:ListDetectors",
          "config:GetComplianceSummaryByConfigRule",
          "cloudtrail:LookupEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "audit_report" {
  name              = "/aws/lambda/${var.name_prefix}-audit-report"
  retention_in_days = 365
  kms_key_id        = var.logs_kms_key_arn
}

resource "aws_lambda_function" "audit_report" {
  function_name    = "${var.name_prefix}-audit-report"
  role             = aws_iam_role.audit_report_lambda.arn
  handler          = "audit_report.handler"
  runtime          = "nodejs20.x"
  filename         = data.archive_file.audit_report.output_path
  source_code_hash = data.archive_file.audit_report.output_base64sha256
  timeout          = 30
  kms_key_arn      = var.logs_kms_key_arn

  environment {
    variables = {
      ALERT_TOPIC_ARN = aws_sns_topic.alerts.arn
      ENVIRONMENT     = var.environment
      PROJECT_NAME    = var.project_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.audit_report]
}

resource "aws_cloudwatch_event_rule" "monthly_audit" {
  name                = "${var.name_prefix}-monthly-audit"
  description         = "Monthly compliance audit automation"
  schedule_expression = "cron(0 1 1 * ? *)"
}

resource "aws_cloudwatch_event_target" "monthly_audit" {
  rule      = aws_cloudwatch_event_rule.monthly_audit.name
  target_id = "audit-report"
  arn       = aws_lambda_function.audit_report.arn
}

resource "aws_lambda_permission" "monthly_audit" {
  statement_id  = "AllowMonthlyAuditEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.audit_report.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.monthly_audit.arn
}

resource "aws_cloudwatch_event_rule" "security_monitoring" {
  for_each = local.security_monitoring_event_rules

  name          = "${var.name_prefix}-${replace(each.key, "_", "-")}"
  description   = each.value.description
  event_pattern = each.value.event_pattern
}

resource "aws_cloudwatch_event_target" "security_monitoring" {
  for_each = local.security_monitoring_event_rules

  rule      = aws_cloudwatch_event_rule.security_monitoring[each.key].name
  target_id = "sns-alerts"
  arn       = aws_sns_topic.alerts.arn

  input_transformer {
    input_paths = {
      account     = "$.account"
      detail_type = "$.detail-type"
      event_name  = "$.detail.eventName"
      principal   = "$.detail.userIdentity.arn"
      region      = "$.region"
      time        = "$.time"
    }

    input_template = "\"${var.name_prefix} security alert: <detail_type> / <event_name> in account <account>, region <region>, principal <principal>, time <time>. Review CloudTrail and related logs.\""
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.name_prefix}-alb-5xx"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
}
