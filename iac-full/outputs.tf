output "vpc_id" {
  description = "Created VPC ID."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = [for subnet in aws_subnet.public : subnet.id]
}

output "app_subnet_ids" {
  description = "Private app subnet IDs."
  value       = [for subnet in aws_subnet.app : subnet.id]
}

output "db_subnet_ids" {
  description = "Isolated DB subnet IDs."
  value       = [for subnet in aws_subnet.db : subnet.id]
}

output "alb_dns_name" {
  description = "Public ALB DNS name."
  value       = aws_lb.app.dns_name
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID."
  value       = aws_cognito_user_pool.main.id
}

output "cognito_web_client_id" {
  description = "Cognito app client ID."
  value       = aws_cognito_user_pool_client.web.id
}

output "rds_endpoint" {
  description = "RDS endpoint."
  value       = aws_db_instance.postgres.address
}

output "rds_master_secret_arn" {
  description = "AWS-managed RDS master user secret ARN."
  value       = aws_db_instance.postgres.master_user_secret[0].secret_arn
  sensitive   = true
}

output "central_logs_bucket" {
  description = "Central log bucket with Object Lock."
  value       = aws_s3_bucket.central_logs.bucket
}

output "operations_admin_role_arn" {
  description = "MFA-protected operations role ARN."
  value       = aws_iam_role.operations_admin.arn
}

output "security_admin_role_arn" {
  description = "MFA-protected security admin role ARN."
  value       = aws_iam_role.security_admin.arn
}

output "auditor_role_arn" {
  description = "MFA-protected read-only auditor role ARN."
  value       = aws_iam_role.auditor.arn
}

output "developer_role_arn" {
  description = "MFA-protected developer role ARN."
  value       = aws_iam_role.developer.arn
}

output "human_iam_users" {
  description = "Human IAM users created for user -> group -> role assume access."
  value       = { for key, user in aws_iam_user.human : key => user.arn }
}

output "human_iam_groups" {
  description = "Human IAM groups that grant sts:AssumeRole to scoped roles."
  value       = { for key, group in aws_iam_group.human : key => group.name }
}
