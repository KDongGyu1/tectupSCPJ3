locals {
  app_services = {
    payment = { name = "payment-api", path = "/payments/*", description = "Payment API" }
    auth    = { name = "auth-user-api", path = "/auth/*", description = "Auth and user API" }
    ops     = { name = "ops-audit-api", path = "/ops/*", description = "Operations and audit API" }
  }

  https_listener_enabled            = var.enable_https_listener && var.alb_certificate_arn != ""
  http_redirect_enabled             = local.https_listener_enabled && var.enable_http_redirect
  cloudfront_origin_protocol_policy = local.https_listener_enabled && var.enable_cloudfront_origin_https ? "https-only" : "http-only"
  cloudfront_custom_certificate     = var.cloudfront_acm_certificate_arn != "" && length(var.cloudfront_aliases) > 0
  cloudfront_origin_domain_name     = var.cloudfront_origin_domain_name != "" ? var.cloudfront_origin_domain_name : aws_lb.app.dns_name
  cloudfront_viewer_mtls_bucket_name = lower(substr(
    "${var.name_prefix}-viewer-mtls-${var.account_id}",
    0,
    63
  ))
  cloudfront_viewer_mtls_trust_store_name = var.cloudfront_viewer_mtls_trust_store_name != "" ? var.cloudfront_viewer_mtls_trust_store_name : "${var.name_prefix}-viewer-mtls"
}
