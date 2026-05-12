variable "name_prefix" { type = string }
variable "account_id" { type = string }
variable "vpc_id" { type = string }
variable "logs_kms_key_arn" { type = string }
variable "enable_log_object_lock" { type = bool }
variable "log_object_lock_retention_days" { type = number }
