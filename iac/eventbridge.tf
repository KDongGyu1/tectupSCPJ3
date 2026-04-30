resource "aws_cloudwatch_event_rule" "daily_compliance_report" {
  name                = "${local.name_prefix}-daily-compliance-report"
  description         = "Generate a regular compliance report for R2/R4/R5 evidence."
  schedule_expression = "rate(1 day)"
}

resource "aws_cloudwatch_event_target" "daily_compliance_report" {
  rule      = aws_cloudwatch_event_rule.daily_compliance_report.name
  target_id = "audit-service"
  arn       = aws_lambda_function.service["audit"].arn

  input = jsonencode({
    action = "generate_compliance_report"
    scope  = ["R2", "R4", "R5"]
  })
}

resource "aws_lambda_permission" "eventbridge_audit" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.service["audit"].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_compliance_report.arn
}
