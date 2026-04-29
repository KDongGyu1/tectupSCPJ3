output "vpc_id" { value = module.network.vpc_id }
output "public_subnet_ids" { value = module.network.public_subnet_ids }
output "app_subnet_ids" { value = module.network.app_subnet_ids }
output "db_subnet_ids" { value = module.network.db_subnet_ids }
output "alb_dns_name" { value = module.app.alb_dns_name }
output "cognito_user_pool_id" { value = module.auth.cognito_user_pool_id }
output "cognito_web_client_id" { value = module.auth.cognito_web_client_id }
output "rds_endpoint" { value = module.data.rds_endpoint }
output "rds_master_secret_arn" {
  value     = module.data.rds_master_secret_arn
  sensitive = true
}
output "central_logs_bucket" { value = module.logging.central_logs_bucket }
output "operations_admin_role_arn" { value = module.iam.operations_admin_role_arn }
output "security_admin_role_arn" { value = module.iam.security_admin_role_arn }
output "auditor_role_arn" { value = module.iam.auditor_role_arn }
