output "alb_arn" { value = aws_lb.app.arn }
output "alb_dns_name" { value = aws_lb.app.dns_name }
output "alb_arn_suffix" { value = aws_lb.app.arn_suffix }
output "alb_http_listener_arn" { value = aws_lb_listener.http.arn }
output "alb_https_listener_arn" { value = try(aws_lb_listener.https[0].arn, null) }
output "cloudfront_distribution_id" { value = aws_cloudfront_distribution.app.id }
output "cloudfront_distribution_domain_name" { value = aws_cloudfront_distribution.app.domain_name }
output "cloudfront_aliases" { value = aws_cloudfront_distribution.app.aliases }
output "cloudfront_origin_domain_name" { value = local.cloudfront_origin_domain_name }
output "cloudfront_standard_logs_bucket" {
  value = var.enable_cloudfront_standard_logs ? aws_s3_bucket.cloudfront_logs[0].bucket : null
}
output "alb_logs_bucket" {
  value = var.enable_alb_access_logs ? aws_s3_bucket.alb_logs[0].bucket : null
}
output "cloudfront_connection_logs_enabled" { value = var.enable_cloudfront_connection_logs }
output "cloudfront_viewer_mtls_enabled" { value = var.enable_cloudfront_viewer_mtls }
output "cloudfront_viewer_mtls_ca_bundle_bucket" { value = try(aws_s3_bucket.cloudfront_viewer_mtls[0].bucket, null) }
output "cloudfront_viewer_mtls_trust_store_name" { value = var.enable_cloudfront_viewer_mtls ? local.cloudfront_viewer_mtls_trust_store_name : null }
output "app_base_url" { value = var.app_base_url != "" ? trimsuffix(var.app_base_url, "/") : "https://${aws_cloudfront_distribution.app.domain_name}" }
output "target_group_arns" { value = { for name, tg in aws_lb_target_group.app : name => tg.arn } }
