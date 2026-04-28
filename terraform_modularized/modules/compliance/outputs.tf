output "guardduty_detector_id" { value = try(aws_guardduty_detector.main[0].id, null) }
output "securityhub_enabled" { value = var.enable_securityhub }
output "aws_config_enabled" { value = var.enable_aws_config }
