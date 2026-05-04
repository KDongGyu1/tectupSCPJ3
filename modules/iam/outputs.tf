output "app_instance_profile_name" { value = aws_iam_instance_profile.app.name }
output "operations_admin_role_arn" { value = aws_iam_role.operations_admin.arn }
output "security_admin_role_arn" { value = aws_iam_role.security_admin.arn }
output "auditor_role_arn" { value = aws_iam_role.auditor.arn }
