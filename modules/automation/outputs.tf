output "alerts_topic_arn" { value = aws_sns_topic.alerts.arn }
output "global_security_alerts_topic_arn" { value = aws_sns_topic.global_security_alerts.arn }
output "audit_report_lambda_name" { value = aws_lambda_function.audit_report.function_name }
output "security_group_change_rule_name" { value = aws_cloudwatch_event_rule.security_group_changes.name }
