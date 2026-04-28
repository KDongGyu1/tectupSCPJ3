variable "name_prefix" { type = string }
variable "db_subnet_ids" { type = list(string) }
variable "db_sg_id" { type = string }
variable "main_kms_key_arn" { type = string }
variable "db_instance_class" { type = string }
variable "db_name" { type = string }
variable "rds_backup_retention_period" { type = number }
