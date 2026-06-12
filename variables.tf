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

variable "enable_cloudfront_origin_only_alb_access" {
  description = "Restrict ALB HTTP/HTTPS ingress to the AWS-managed CloudFront origin-facing prefix list."
  type        = bool
  default     = false
}

variable "alb_certificate_arn" {
  description = "Deprecated alias for acm_certificate_arn. Optional ACM certificate ARN for HTTPS listener."
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "Optional ACM certificate ARN for ALB HTTPS listener. Overrides alb_certificate_arn when set."
  type        = string
  default     = ""
}

variable "enable_https_listener" {
  description = "Create the ALB HTTPS listener when an ACM certificate ARN is provided."
  type        = bool
  default     = false
}

variable "enable_http_redirect" {
  description = "Redirect ALB HTTP requests to HTTPS when the HTTPS listener is enabled."
  type        = bool
  default     = false
}

variable "enable_cloudfront_origin_https" {
  description = "Use HTTPS from CloudFront to the ALB. Requires enable_https_listener and an ACM certificate ARN."
  type        = bool
  default     = false
}

variable "cloudfront_aliases" {
  description = "Optional custom domain aliases for the CloudFront distribution. Requires a us-east-1 ACM certificate."
  type        = list(string)
  default     = []
}

variable "cloudfront_acm_certificate_arn" {
  description = "Optional us-east-1 ACM certificate ARN for CloudFront custom aliases."
  type        = string
  default     = ""
}

variable "cloudfront_origin_domain_name" {
  description = "Optional custom origin DNS name for CloudFront to reach the ALB, such as origin.example.com. Required when CloudFront origin HTTPS uses an ALB certificate for that hostname."
  type        = string
  default     = ""
}

variable "enable_cloudfront_standard_logs" {
  description = "Store CloudFront standard access logs in a dedicated S3 bucket."
  type        = bool
  default     = true
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

variable "rds_sslmode" {
  description = "PostgreSQL client sslmode used by the app when connecting to RDS."
  type        = string
  default     = "require"

  validation {
    condition     = contains(["disable", "allow", "prefer", "require", "verify-ca", "verify-full"], var.rds_sslmode)
    error_message = "rds_sslmode must be one of disable, allow, prefer, require, verify-ca, or verify-full."
  }
}

variable "app_base_url" {
  description = "Optional public application base URL override used for Cognito Hosted UI callback and logout URLs. Leave empty to use the CloudFront distribution URL."
  type        = string
  default     = ""
}

variable "cognito_domain_prefix" {
  description = "Optional Cognito hosted UI domain prefix. Must be unique in the AWS region."
  type        = string
  default     = ""
}

variable "enable_alb_access_logs" {
  description = "Enable ALB access logs. Keep false when using the KMS/Object Lock central log bucket because ALB log delivery has stricter S3 requirements."
  type        = bool
  default     = false
}

variable "s3_gateway_endpoint_bucket_arns" {
  description = "Additional S3 bucket/object ARNs allowed through the S3 Gateway Endpoint policy."
  type        = list(string)
  default     = []
}

variable "enable_interface_endpoint_policy_restrictions" {
  description = "Apply service-scoped policies to Interface Endpoints. Keep false until SSM and runtime calls are verified."
  type        = bool
  default     = false
}

variable "waf_rate_rule_action" {
  description = "Action for custom WAF rate-based rules."
  type        = string
  default     = "count"

  validation {
    condition     = contains(["count", "block"], var.waf_rate_rule_action)
    error_message = "waf_rate_rule_action must be count or block."
  }
}

variable "waf_rate_limits" {
  description = "Path-specific WAF rate limits evaluated per source IP."
  type = object({
    auth         = number
    payments     = number
    transactions = number
    ops          = number
    audit        = number
  })
  default = {
    auth         = 300
    payments     = 500
    transactions = 1000
    ops          = 100
    audit        = 100
  }
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

variable "enable_log_object_lock" {
  description = "Enable default S3 Object Lock retention on the central log bucket. Keep false for repeatable dev destroy/apply cycles."
  type        = bool
  default     = false
}

variable "log_object_lock_retention_days" {
  description = "Central log bucket Object Lock retention days."
  type        = number
  default     = 365
}
