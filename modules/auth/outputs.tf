output "cognito_user_pool_id" { value = aws_cognito_user_pool.main.id }
output "cognito_web_client_id" { value = aws_cognito_user_pool_client.web.id }
output "cognito_hosted_ui_domain" { value = aws_cognito_user_pool_domain.main.domain }
output "cognito_hosted_ui_base_url" {
  value = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
}
