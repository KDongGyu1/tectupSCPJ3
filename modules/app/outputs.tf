output "alb_arn" { value = aws_lb.app.arn }
output "alb_dns_name" { value = aws_lb.app.dns_name }
output "alb_arn_suffix" { value = aws_lb.app.arn_suffix }
output "cloudfront_distribution_domain_name" { value = aws_cloudfront_distribution.app.domain_name }
output "app_base_url" { value = var.app_base_url != "" ? trimsuffix(var.app_base_url, "/") : "https://${aws_cloudfront_distribution.app.domain_name}" }
output "target_group_arns" { value = { for name, tg in aws_lb_target_group.app : name => tg.arn } }
