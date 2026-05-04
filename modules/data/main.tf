resource "aws_db_subnet_group" "main" {
  name       = "${var.name_prefix}-db-subnet-group"
  subnet_ids = var.db_subnet_ids
}

resource "aws_db_instance" "postgres" {
  identifier                          = "${var.name_prefix}-postgres"
  engine                              = "postgres"
  instance_class                      = var.db_instance_class
  allocated_storage                   = 20
  max_allocated_storage               = 100
  storage_encrypted                   = true
  kms_key_id                          = var.main_kms_key_arn
  db_name                             = var.db_name
  username                            = "finpay_admin"
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = var.main_kms_key_arn
  db_subnet_group_name                = aws_db_subnet_group.main.name
  vpc_security_group_ids              = [var.db_sg_id]
  backup_retention_period             = var.rds_backup_retention_period
  deletion_protection                 = false
  skip_final_snapshot                 = true
  publicly_accessible                 = false
  multi_az                            = true
  performance_insights_enabled        = true
  performance_insights_kms_key_id     = var.main_kms_key_arn
  iam_database_authentication_enabled = true
  auto_minor_version_upgrade          = true

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
}
