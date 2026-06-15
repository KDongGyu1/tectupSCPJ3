variable "name_prefix" { type = string }
variable "account_id" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "app_subnet_ids" { type = list(string) }
variable "alb_sg_id" { type = string }
variable "app_sg_id" { type = string }
variable "app_instance_profile_name" { type = string }
variable "logs_kms_key_arn" { type = string }
variable "central_logs_bucket" { type = string }
variable "enable_alb_access_logs" { type = bool }
variable "alb_certificate_arn" { type = string }
variable "enable_https_listener" { type = bool }
variable "enable_http_redirect" { type = bool }
variable "enable_cloudfront_origin_https" { type = bool }
variable "cloudfront_aliases" { type = list(string) }
variable "cloudfront_acm_certificate_arn" { type = string }
variable "cloudfront_origin_domain_name" { type = string }
variable "enable_cloudfront_standard_logs" { type = bool }
variable "enable_cloudfront_connection_logs" { type = bool }
variable "enable_cloudfront_viewer_mtls" { type = bool }
variable "cloudfront_viewer_mtls_mode" { type = string }
variable "cloudfront_viewer_mtls_ca_bundle_path" { type = string }
variable "cloudfront_viewer_mtls_ca_bundle_s3_key" { type = string }
variable "cloudfront_viewer_mtls_trust_store_name" { type = string }
variable "cloudfront_viewer_mtls_advertise_ca_names" { type = bool }
variable "cloudfront_viewer_mtls_ignore_certificate_expiry" { type = bool }
variable "cloudfront_viewer_mtls_aws_profile" { type = string }
variable "app_instance_type" { type = string }
variable "app_desired_capacity" { type = number }
variable "app_min_size" { type = number }
variable "app_max_size" { type = number }
variable "cognito_user_pool_id" { type = string }
variable "cognito_web_client_id" { type = string }
variable "cognito_hosted_ui_base_url" { type = string }
variable "app_base_url" { type = string }
variable "rds_endpoint" { type = string }
variable "rds_master_secret_arn" { type = string }
variable "rds_sslmode" { type = string }
variable "aws_region" { type = string }
variable "app_artifact_bucket" { type = string }
variable "app_artifact_key" { type = string }

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      configuration_aliases = [
        aws.global_events
      ]
    }
  }
}
