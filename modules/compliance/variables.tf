variable "name_prefix" { type = string }
variable "aws_region" { type = string }
variable "central_logs_bucket" { type = string }
variable "logs_kms_key_arn" { type = string }
variable "enable_guardduty" { type = bool }
variable "enable_securityhub" { type = bool }
variable "enable_aws_config" { type = bool }
