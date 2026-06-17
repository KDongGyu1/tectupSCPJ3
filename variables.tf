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

variable "enable_alb_to_app_https" {
  description = "Use HTTPS from the ALB target group to the EC2 app instances. The app instances generate a local TLS certificate at boot."
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

variable "enable_cloudfront_connection_logs" {
  description = "Store CloudFront viewer mTLS connection logs in the existing CloudFront log S3 bucket."
  type        = bool
  default     = false
}

variable "enable_cloudfront_viewer_mtls" {
  description = "Require or request client certificates at the CloudFront viewer edge using a CloudFront trust store."
  type        = bool
  default     = false
}

variable "cloudfront_viewer_mtls_mode" {
  description = "CloudFront viewer mTLS mode. Use required to block clients without a trusted certificate, or optional to request a certificate without requiring it."
  type        = string
  default     = "required"

  validation {
    condition     = contains(["required", "optional"], var.cloudfront_viewer_mtls_mode)
    error_message = "cloudfront_viewer_mtls_mode must be required or optional."
  }
}

variable "cloudfront_viewer_mtls_ca_bundle_path" {
  description = "Local path to the PEM CA bundle that CloudFront will trust for viewer client certificates."
  type        = string
  default     = "certs/mtls/client-ca-bundle.pem"
}

variable "cloudfront_viewer_mtls_ca_bundle_s3_key" {
  description = "S3 object key used to store the CloudFront viewer mTLS CA bundle."
  type        = string
  default     = "cloudfront-viewer-mtls/client-ca-bundle.pem"
}

variable "cloudfront_viewer_mtls_trust_store_name" {
  description = "Optional CloudFront trust store name. Leave empty to use the environment-specific default."
  type        = string
  default     = ""
}

variable "cloudfront_viewer_mtls_advertise_ca_names" {
  description = "Advertise the trusted CA names to viewers during the TLS client certificate request."
  type        = bool
  default     = true
}

variable "cloudfront_viewer_mtls_ignore_certificate_expiry" {
  description = "Ignore viewer client certificate expiry during CloudFront mTLS validation. Keep false for normal security posture."
  type        = bool
  default     = false
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

variable "standard_cloudwatch_log_retention_days" {
  description = "CloudWatch retention days for standard operational logs. CloudWatch supports fixed values; 365 satisfies the one-year baseline."
  type        = number
  default     = 365
}

variable "audit_cloudwatch_log_retention_days" {
  description = "CloudWatch retention days for audit-sensitive logs. Use 731 for a two-year CloudWatch retention because 730 is not a supported CloudWatch value."
  type        = number
  default     = 731
}

variable "log_lifecycle_transition_ia_days" {
  description = "Days before S3 log objects transition from Standard to Standard-IA."
  type        = number
  default     = 90
}

variable "log_lifecycle_transition_glacier_days" {
  description = "Days before S3 log objects transition to Glacier Flexible Retrieval."
  type        = number
  default     = 180
}

variable "alb_log_lifecycle_expiration_days" {
  description = "Days before ALB access log objects expire."
  type        = number
  default     = 365

  validation {
    condition     = contains([365, 730], var.alb_log_lifecycle_expiration_days)
    error_message = "alb_log_lifecycle_expiration_days must be either 365 or 730."
  }
}

variable "central_log_lifecycle_expiration_days" {
  description = "Days before central S3 audit log objects expire. 730 days is the operating target for important audit evidence."
  type        = number
  default     = 730
}

variable "cloudfront_standard_log_lifecycle_expiration_days" {
  description = "Days before CloudFront standard access log objects expire."
  type        = number
  default     = 365
}

variable "cloudfront_connection_log_lifecycle_expiration_days" {
  description = "Days before CloudFront connection log objects expire. These logs include viewer mTLS authentication evidence."
  type        = number
  default     = 730
}
