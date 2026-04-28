resource "aws_sns_topic" "alerts" {
  name              = "${local.name_prefix}-alerts"
  kms_master_key_id = aws_kms_key.logs.arn
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

data "archive_file" "audit_report" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/audit_report.js"
  output_path = "${path.module}/.terraform-build/audit_report.zip"
}

resource "aws_iam_role" "audit_report_lambda" {
  name = "${local.name_prefix}-audit-report-lambda-role"

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
  name = "${local.name_prefix}-audit-report-policy"
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
  name              = "/aws/lambda/${local.name_prefix}-audit-report"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.logs.arn
}

resource "aws_lambda_function" "audit_report" {
  function_name    = "${local.name_prefix}-audit-report"
  role             = aws_iam_role.audit_report_lambda.arn
  handler          = "audit_report.handler"
  runtime          = "nodejs20.x"
  filename         = data.archive_file.audit_report.output_path
  source_code_hash = data.archive_file.audit_report.output_base64sha256
  timeout          = 30
  kms_key_arn      = aws_kms_key.logs.arn

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
  name                = "${local.name_prefix}-monthly-audit"
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

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name_prefix}-alb-5xx"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
  }
}

