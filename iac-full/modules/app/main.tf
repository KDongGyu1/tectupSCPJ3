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

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app["payment"].arn
  }
}

resource "aws_lb_listener" "https" {
  count = var.alb_certificate_arn == "" ? 0 : 1

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
  for_each = local.app_services

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

resource "aws_lb_listener_rule" "https_paths" {
  for_each = var.alb_certificate_arn == "" ? {} : local.app_services

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
    service_name = each.value.name
    environment  = var.environment
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

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-${each.key}"
    propagate_at_launch = true
  }
}
