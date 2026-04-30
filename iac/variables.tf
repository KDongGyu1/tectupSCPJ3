variable "project_name" {
  description = "Project name used as the resource prefix."
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

variable "vpc_id" {
  description = "Existing VPC ID. Network is managed outside this stack."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private/internal subnet IDs for regulated workloads and data stores."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs, if needed for public-facing managed resources."
  type        = list(string)
  default     = []
}

variable "allowed_admin_cidr_blocks" {
  description = "CIDRs allowed to reach the API. Tighten this for admin or private deployments."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "create_rds" {
  description = "Create PostgreSQL RDS instances for user/transaction DBs."
  type        = bool
  default     = false
}

variable "create_redis" {
  description = "Create ElastiCache Redis for JWT/session storage."
  type        = bool
  default     = false
}

variable "db_name" {
  description = "Initial application database name."
  type        = string
  default     = "finpay"
}

variable "db_username" {
  description = "RDS master username."
  type        = string
  default     = "finpay_admin"
}

variable "db_password" {
  description = "RDS master password. Required when create_rds is true."
  type        = string
  default     = null
  sensitive   = true
}

variable "pg_endpoint_url" {
  description = "Registered PG provider endpoint URL."
  type        = string
  default     = ""
}

variable "bank_endpoint_url" {
  description = "Bank/card company endpoint URL."
  type        = string
  default     = ""
}

variable "fiu_endpoint_url" {
  description = "FIU STR/CTR reporting endpoint URL."
  type        = string
  default     = ""
}

variable "dispute_endpoint_url" {
  description = "Financial dispute mediation endpoint URL."
  type        = string
  default     = ""
}

variable "alert_email" {
  description = "Email address for compliance/security alerts. Leave empty to skip subscription."
  type        = string
  default     = ""
}
