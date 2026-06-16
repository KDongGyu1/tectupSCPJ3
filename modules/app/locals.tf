locals {
  app_services = {
    payment = { name = "payment-api", path = "/payments/*", description = "Payment API" }
    auth    = { name = "auth-user-api", path = "/auth/*", description = "Auth and user API" }
    ops     = { name = "ops-audit-api", path = "/ops/*", description = "Operations and audit API" }
  }

  https_listener_enabled            = var.enable_https_listener && var.alb_certificate_arn != ""
  http_redirect_enabled             = local.https_listener_enabled && var.enable_http_redirect
  cloudfront_origin_protocol_policy = local.https_listener_enabled && var.enable_cloudfront_origin_https ? "https-only" : "http-only"
  app_target_protocol               = var.enable_alb_to_app_https ? "HTTPS" : "HTTP"
  cloudfront_custom_certificate     = var.cloudfront_acm_certificate_arn != "" && length(var.cloudfront_aliases) > 0
  cloudfront_origin_domain_name     = var.cloudfront_origin_domain_name != "" ? var.cloudfront_origin_domain_name : aws_lb.app.dns_name
  cloudfront_viewer_mtls_bucket_name = lower(substr(
    "${var.name_prefix}-viewer-mtls-${var.account_id}",
    0,
    63
  ))
  cloudfront_viewer_mtls_trust_store_name = var.cloudfront_viewer_mtls_trust_store_name != "" ? var.cloudfront_viewer_mtls_trust_store_name : "${var.name_prefix}-viewer-mtls"
  cloudfront_managed_config_hash = sha1(jsonencode({
    aliases                  = local.cloudfront_custom_certificate ? var.cloudfront_aliases : []
    certificate_arn          = local.cloudfront_custom_certificate ? var.cloudfront_acm_certificate_arn : ""
    enable_alb_to_app_https  = var.enable_alb_to_app_https
    enable_connection_logs   = var.enable_cloudfront_connection_logs
    enable_standard_logs     = var.enable_cloudfront_standard_logs
    minimum_protocol_version = "TLSv1.2_2021"
    origin_domain_name       = local.cloudfront_origin_domain_name
    origin_protocol_policy   = local.cloudfront_origin_protocol_policy
    standard_logs_bucket     = var.enable_cloudfront_standard_logs ? try(aws_s3_bucket.cloudfront_logs[0].bucket_domain_name, "") : ""
    viewer_protocol_policy   = "redirect-to-https"
  }))
}
