output "api_endpoint" {
  description = "HTTP API endpoint."
  value       = aws_apigatewayv2_api.http.api_endpoint
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID."
  value       = aws_cognito_user_pool.main.id
}

output "cognito_web_client_id" {
  description = "Cognito web client ID."
  value       = aws_cognito_user_pool_client.web.id
}

output "audit_worm_bucket" {
  description = "S3 Object Lock bucket for CloudTrail and audit evidence."
  value       = aws_s3_bucket.audit_worm.bucket
}

output "event_queue_url" {
  description = "Encrypted application event queue URL."
  value       = aws_sqs_queue.events.url
}

output "auditor_readonly_policy_arn" {
  description = "IAM policy ARN for auditor read-only access."
  value       = aws_iam_policy.auditor_readonly.arn
}

output "rds_endpoint" {
  description = "RDS endpoint when create_rds is true."
  value       = var.create_rds ? aws_db_instance.postgres[0].address : null
}

output "redis_endpoint" {
  description = "Redis endpoint when create_redis is true."
  value       = var.create_redis ? aws_elasticache_replication_group.redis[0].primary_endpoint_address : null
}
