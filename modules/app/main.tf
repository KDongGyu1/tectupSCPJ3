data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_cloudwatch_log_group" "app" {
  for_each          = local.app_services
  name              = "/finpay/${var.name_prefix}/${each.key}"
  retention_in_days = 365
  kms_key_id        = var.logs_kms_key_arn
}

resource "aws_lb" "app" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids
  idle_timeout       = 60

  enable_deletion_protection = false
  drop_invalid_header_fields = true

  dynamic "access_logs" {
    for_each = var.enable_alb_access_logs ? [1] : []

    content {
      bucket  = var.central_logs_bucket
      prefix  = "alb"
      enabled = true
    }
  }

}

resource "aws_cloudfront_distribution" "app" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${var.name_prefix} application HTTPS entry point"
  price_class     = "PriceClass_200"
  aliases         = local.cloudfront_custom_certificate ? var.cloudfront_aliases : []

  origin {
    domain_name = local.cloudfront_origin_domain_name
    origin_id   = "${var.name_prefix}-alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = local.cloudfront_origin_protocol_policy
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "${var.name_prefix}-alb-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0

    forwarded_values {
      query_string = true

      cookies {
        forward = "all"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = !local.cloudfront_custom_certificate
    acm_certificate_arn            = local.cloudfront_custom_certificate ? var.cloudfront_acm_certificate_arn : null
    ssl_support_method             = local.cloudfront_custom_certificate ? "sni-only" : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }
}

resource "aws_s3_bucket" "cloudfront_viewer_mtls" {
  count = var.enable_cloudfront_viewer_mtls ? 1 : 0

  bucket        = local.cloudfront_viewer_mtls_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "cloudfront_viewer_mtls" {
  count = var.enable_cloudfront_viewer_mtls ? 1 : 0

  bucket                  = aws_s3_bucket.cloudfront_viewer_mtls[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "cloudfront_viewer_mtls" {
  count = var.enable_cloudfront_viewer_mtls ? 1 : 0

  bucket = aws_s3_bucket.cloudfront_viewer_mtls[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudfront_viewer_mtls" {
  count = var.enable_cloudfront_viewer_mtls ? 1 : 0

  bucket = aws_s3_bucket.cloudfront_viewer_mtls[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "cloudfront_viewer_mtls" {
  count = var.enable_cloudfront_viewer_mtls ? 1 : 0

  statement {
    sid = "AllowCloudFrontTrustStoreRead"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
    ]

    resources = [
      "${aws_s3_bucket.cloudfront_viewer_mtls[0].arn}/${var.cloudfront_viewer_mtls_ca_bundle_s3_key}",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudfront_viewer_mtls" {
  count = var.enable_cloudfront_viewer_mtls ? 1 : 0

  bucket = aws_s3_bucket.cloudfront_viewer_mtls[0].id
  policy = data.aws_iam_policy_document.cloudfront_viewer_mtls[0].json
}

resource "aws_s3_object" "cloudfront_viewer_mtls_ca_bundle" {
  count = var.enable_cloudfront_viewer_mtls ? 1 : 0

  bucket       = aws_s3_bucket.cloudfront_viewer_mtls[0].id
  key          = var.cloudfront_viewer_mtls_ca_bundle_s3_key
  source       = var.cloudfront_viewer_mtls_ca_bundle_path
  etag         = filemd5(var.cloudfront_viewer_mtls_ca_bundle_path)
  content_type = "application/x-pem-file"

  depends_on = [
    aws_s3_bucket_public_access_block.cloudfront_viewer_mtls,
    aws_s3_bucket_versioning.cloudfront_viewer_mtls,
    aws_s3_bucket_server_side_encryption_configuration.cloudfront_viewer_mtls,
    aws_s3_bucket_policy.cloudfront_viewer_mtls,
  ]
}

resource "terraform_data" "cloudfront_viewer_mtls_apply" {
  count = var.enable_cloudfront_viewer_mtls ? 1 : 0

  input = {
    advertise_ca_names = tostring(var.cloudfront_viewer_mtls_advertise_ca_names)
    aws_profile        = var.cloudfront_viewer_mtls_aws_profile
    ca_bundle_bucket   = aws_s3_bucket.cloudfront_viewer_mtls[0].bucket
    ca_bundle_key      = aws_s3_object.cloudfront_viewer_mtls_ca_bundle[0].key
    ca_bundle_region   = var.aws_region
    ca_bundle_version  = try(aws_s3_object.cloudfront_viewer_mtls_ca_bundle[0].version_id, "")
    distribution_id    = aws_cloudfront_distribution.app.id
    ignore_certificate_expiry = tostring(
      var.cloudfront_viewer_mtls_ignore_certificate_expiry
    )
    mode             = var.cloudfront_viewer_mtls_mode
    script_path      = "${path.root}/scripts/cloudfront-viewer-mtls.sh"
    trust_store_name = local.cloudfront_viewer_mtls_trust_store_name
  }

  triggers_replace = [
    aws_cloudfront_distribution.app.id,
    aws_s3_object.cloudfront_viewer_mtls_ca_bundle[0].etag,
    try(aws_s3_object.cloudfront_viewer_mtls_ca_bundle[0].version_id, ""),
    var.cloudfront_viewer_mtls_mode,
    tostring(var.cloudfront_viewer_mtls_advertise_ca_names),
    tostring(var.cloudfront_viewer_mtls_ignore_certificate_expiry),
  ]

  provisioner "local-exec" {
    command = "${self.input.script_path} apply"

    environment = {
      ADVERTISE_CA_NAMES        = self.input.advertise_ca_names
      AWS_PROFILE               = self.input.aws_profile
      CA_BUNDLE_BUCKET          = self.input.ca_bundle_bucket
      CA_BUNDLE_KEY             = self.input.ca_bundle_key
      CA_BUNDLE_REGION          = self.input.ca_bundle_region
      CA_BUNDLE_VERSION         = self.input.ca_bundle_version
      DISTRIBUTION_ID           = self.input.distribution_id
      IGNORE_CERTIFICATE_EXPIRY = self.input.ignore_certificate_expiry
      TRUST_STORE_NAME          = self.input.trust_store_name
      VIEWER_MTLS_MODE          = self.input.mode
    }
  }

  lifecycle {
    precondition {
      condition     = local.cloudfront_custom_certificate
      error_message = "CloudFront viewer mTLS requires cloudfront_aliases and cloudfront_acm_certificate_arn."
    }
  }

  depends_on = [
    aws_cloudfront_distribution.app,
    aws_s3_object.cloudfront_viewer_mtls_ca_bundle,
  ]
}

resource "terraform_data" "cloudfront_viewer_mtls_cleanup" {
  count = var.enable_cloudfront_viewer_mtls ? 1 : 0

  input = {
    aws_profile      = var.cloudfront_viewer_mtls_aws_profile
    distribution_id  = aws_cloudfront_distribution.app.id
    script_path      = "${path.root}/scripts/cloudfront-viewer-mtls.sh"
    trust_store_name = local.cloudfront_viewer_mtls_trust_store_name
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${self.input.script_path} destroy"

    environment = {
      AWS_PROFILE      = self.input.aws_profile
      DISTRIBUTION_ID  = self.input.distribution_id
      TRUST_STORE_NAME = self.input.trust_store_name
    }
  }

  depends_on = [
    terraform_data.cloudfront_viewer_mtls_apply,
  ]
}

resource "aws_lb_target_group" "app" {
  for_each = local.app_services

  name        = "${var.name_prefix}-${each.key}-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = "80"
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = local.http_redirect_enabled ? [1] : []

    content {
      type = "redirect"

      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = local.http_redirect_enabled ? [] : [1]

    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.app["payment"].arn
    }
  }
}

resource "aws_lb_listener" "https" {
  count = local.https_listener_enabled ? 1 : 0

  load_balancer_arn = aws_lb.app.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.alb_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app["payment"].arn
  }
}

resource "aws_lb_listener_rule" "http_paths" {
  for_each = local.http_redirect_enabled ? {} : local.app_services

  listener_arn = aws_lb_listener.http.arn
  priority     = index(keys(local.app_services), each.key) + 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[each.key].arn
  }

  condition {
    path_pattern {
      values = [each.value.path]
    }
  }
}

resource "aws_lb_listener_rule" "http_app_auth_paths" {
  count = local.http_redirect_enabled ? 0 : 1

  listener_arn = aws_lb_listener.http.arn
  priority     = 5

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app["payment"].arn
  }

  condition {
    path_pattern {
      values = [
        "/auth/login",
        "/auth/logout",
        "/auth/callback",
        "/auth/cognito/*",
      ]
    }
  }
}

resource "aws_lb_listener_rule" "https_paths" {
  for_each = local.https_listener_enabled ? local.app_services : {}

  listener_arn = aws_lb_listener.https[0].arn
  priority     = index(keys(local.app_services), each.key) + 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[each.key].arn
  }

  condition {
    path_pattern {
      values = [each.value.path]
    }
  }
}

resource "aws_lb_listener_rule" "https_app_auth_paths" {
  count = local.https_listener_enabled ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 5

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app["payment"].arn
  }

  condition {
    path_pattern {
      values = [
        "/auth/login",
        "/auth/logout",
        "/auth/callback",
        "/auth/cognito/*",
      ]
    }
  }
}

resource "aws_launch_template" "app" {
  for_each = local.app_services

  name_prefix   = "${var.name_prefix}-${each.key}-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.app_instance_type

  iam_instance_profile {
    name = var.app_instance_profile_name
  }

  vpc_security_group_ids = [var.app_sg_id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    service_name          = each.value.name
    service_key           = each.key
    service_description   = each.value.description
    service_route_prefix  = replace(each.value.path, "/*", "")
    environment           = var.environment
    aws_region            = var.aws_region
    name_prefix           = var.name_prefix
    cognito_user_pool_id  = var.cognito_user_pool_id
    cognito_web_client_id = var.cognito_web_client_id
    cognito_hosted_ui_url = var.cognito_hosted_ui_base_url
    app_base_url          = var.app_base_url != "" ? trimsuffix(var.app_base_url, "/") : "https://${aws_cloudfront_distribution.app.domain_name}"
    rds_endpoint          = var.rds_endpoint
    rds_master_secret_arn = var.rds_master_secret_arn
    rds_sslmode           = var.rds_sslmode
    app_artifact_bucket   = var.app_artifact_bucket
    app_artifact_key      = var.app_artifact_key
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "${var.name_prefix}-${each.key}"
      Service = each.value.name
    }
  }
}

resource "aws_autoscaling_group" "app" {
  for_each = local.app_services

  name                = "${var.name_prefix}-${each.key}-asg"
  vpc_zone_identifier = var.app_subnet_ids
  min_size            = var.app_min_size
  max_size            = var.app_max_size
  desired_capacity    = var.app_desired_capacity
  health_check_type   = "ELB"
  target_group_arns   = [aws_lb_target_group.app[each.key].arn]

  launch_template {
    id      = aws_launch_template.app[each.key].id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-${each.key}"
    propagate_at_launch = true
  }
}
