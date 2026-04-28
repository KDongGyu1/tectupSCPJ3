variable "project_name" {
  description = "Project name used as resource prefix."
  type        = string
  default     = "finpay"
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "ap-northeast-2"
}

variable "aws_profile" {
  description = "Optional local AWS CLI profile to use as the source credentials."
  type        = string
  default     = ""
}

variable "assume_role_arn" {
  description = "Optional AWS IAM role ARN for Terraform to assume before creating resources."
  type        = string
  default     = ""
}

variable "assume_role_session_name" {
  description = "Session name used when assume_role_arn is set."
  type        = string
  default     = "finpay-terraform"
}

variable "vpc_cidr" {
  description = "VPC CIDR."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_names" {
  description = "AZs for the 2-AZ deployment."
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs."
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "app_subnet_cidrs" {
  description = "Private app subnet CIDRs."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "db_subnet_cidrs" {
  description = "Isolated DB subnet CIDRs."
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "allowed_http_cidr_blocks" {
  description = "CIDRs allowed to reach the public ALB."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "alb_certificate_arn" {
  description = "Optional ACM certificate ARN for HTTPS listener."
  type        = string
  default     = ""
}

variable "app_instance_type" {
  description = "EC2 instance type for app ASGs."
  type        = string
  default     = "t3.micro"
}

variable "app_desired_capacity" {
  description = "Desired capacity per app ASG."
  type        = number
  default     = 1
}

variable "app_min_size" {
  description = "Minimum size per app ASG."
  type        = number
  default     = 1
}

variable "app_max_size" {
  description = "Maximum size per app ASG."
  type        = number
  default     = 2
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_name" {
  description = "Initial RDS database name."
  type        = string
  default     = "finpay"
}

variable "alert_email" {
  description = "Optional email target for SNS alerts."
  type        = string
  default     = ""
}

variable "enable_alb_access_logs" {
  description = "Enable ALB access logs. Keep false when using the KMS/Object Lock central log bucket because ALB log delivery has stricter S3 requirements."
  type        = bool
  default     = false
}

variable "enable_guardduty" {
  description = "Enable GuardDuty. Some AWS accounts require service subscription/activation first."
  type        = bool
  default     = false
}

variable "enable_securityhub" {
  description = "Enable Security Hub. Some AWS accounts require service subscription/activation first."
  type        = bool
  default     = false
}

variable "enable_aws_config" {
  description = "Enable AWS Config recorder and managed rules. Some lab/free accounts reject Config delivery policies with locked or KMS-encrypted buckets."
  type        = bool
  default     = false
}

variable "rds_backup_retention_period" {
  description = "RDS automated backup retention days. Free tier accounts commonly allow up to 7."
  type        = number
  default     = 1
}

variable "log_object_lock_retention_days" {
  description = "Central log bucket Object Lock retention days."
  type        = number
  default     = 365
}
