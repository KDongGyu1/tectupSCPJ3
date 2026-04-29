output "alerts_topic_arn" { value = aws_sns_topic.alerts.arn }
output "audit_report_lambda_name" { value = aws_lambda_function.audit_report.function_name }
