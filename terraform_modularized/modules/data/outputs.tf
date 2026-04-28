output "rds_endpoint" { value = aws_db_instance.postgres.address }
output "rds_arn" { value = aws_db_instance.postgres.arn }
output "rds_master_secret_arn" {
  value     = aws_db_instance.postgres.master_user_secret[0].secret_arn
  sensitive = true
}
