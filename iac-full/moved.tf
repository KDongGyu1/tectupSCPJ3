moved {
  from = aws_autoscaling_group.app["auth"]
  to   = module.app.aws_autoscaling_group.app["auth"]
}

moved {
  from = aws_autoscaling_group.app["ops"]
  to   = module.app.aws_autoscaling_group.app["ops"]
}

moved {
  from = aws_autoscaling_group.app["payment"]
  to   = module.app.aws_autoscaling_group.app["payment"]
}

moved {
  from = aws_cloudwatch_log_group.app["auth"]
  to   = module.app.aws_cloudwatch_log_group.app["auth"]
}

moved {
  from = aws_cloudwatch_log_group.app["ops"]
  to   = module.app.aws_cloudwatch_log_group.app["ops"]
}

moved {
  from = aws_cloudwatch_log_group.app["payment"]
  to   = module.app.aws_cloudwatch_log_group.app["payment"]
}

moved {
  from = aws_launch_template.app["auth"]
  to   = module.app.aws_launch_template.app["auth"]
}

moved {
  from = aws_launch_template.app["ops"]
  to   = module.app.aws_launch_template.app["ops"]
}

moved {
  from = aws_launch_template.app["payment"]
  to   = module.app.aws_launch_template.app["payment"]
}

moved {
  from = aws_lb.app
  to   = module.app.aws_lb.app
}

moved {
  from = aws_lb_listener.http
  to   = module.app.aws_lb_listener.http
}

moved {
  from = aws_lb_listener_rule.http_paths["auth"]
  to   = module.app.aws_lb_listener_rule.http_paths["auth"]
}

moved {
  from = aws_lb_listener_rule.http_paths["ops"]
  to   = module.app.aws_lb_listener_rule.http_paths["ops"]
}

moved {
  from = aws_lb_listener_rule.http_paths["payment"]
  to   = module.app.aws_lb_listener_rule.http_paths["payment"]
}

moved {
  from = aws_lb_target_group.app["auth"]
  to   = module.app.aws_lb_target_group.app["auth"]
}

moved {
  from = aws_lb_target_group.app["ops"]
  to   = module.app.aws_lb_target_group.app["ops"]
}

moved {
  from = aws_lb_target_group.app["payment"]
  to   = module.app.aws_lb_target_group.app["payment"]
}

moved {
  from = aws_cognito_user_group.rbac["Auditor"]
  to   = module.auth.aws_cognito_user_group.rbac["Auditor"]
}

moved {
  from = aws_cognito_user_group.rbac["Customer"]
  to   = module.auth.aws_cognito_user_group.rbac["Customer"]
}

moved {
  from = aws_cognito_user_group.rbac["Merchant"]
  to   = module.auth.aws_cognito_user_group.rbac["Merchant"]
}

moved {
  from = aws_cognito_user_group.rbac["OperationsAdmin"]
  to   = module.auth.aws_cognito_user_group.rbac["OperationsAdmin"]
}

moved {
  from = aws_cognito_user_group.rbac["SecurityAdmin"]
  to   = module.auth.aws_cognito_user_group.rbac["SecurityAdmin"]
}

moved {
  from = aws_cognito_user_group.rbac["SettlementOperator"]
  to   = module.auth.aws_cognito_user_group.rbac["SettlementOperator"]
}

moved {
  from = aws_cognito_user_pool.main
  to   = module.auth.aws_cognito_user_pool.main
}

moved {
  from = aws_cognito_user_pool_client.web
  to   = module.auth.aws_cognito_user_pool_client.web
}

moved {
  from = aws_cloudwatch_event_rule.monthly_audit
  to   = module.automation.aws_cloudwatch_event_rule.monthly_audit
}

moved {
  from = aws_cloudwatch_event_target.monthly_audit
  to   = module.automation.aws_cloudwatch_event_target.monthly_audit
}

moved {
  from = aws_cloudwatch_log_group.audit_report
  to   = module.automation.aws_cloudwatch_log_group.audit_report
}

moved {
  from = aws_cloudwatch_metric_alarm.alb_5xx
  to   = module.automation.aws_cloudwatch_metric_alarm.alb_5xx
}

moved {
  from = aws_iam_role.audit_report_lambda
  to   = module.automation.aws_iam_role.audit_report_lambda
}

moved {
  from = aws_iam_role_policy.audit_report
  to   = module.automation.aws_iam_role_policy.audit_report
}

moved {
  from = aws_iam_role_policy_attachment.audit_report_basic
  to   = module.automation.aws_iam_role_policy_attachment.audit_report_basic
}

moved {
  from = aws_lambda_function.audit_report
  to   = module.automation.aws_lambda_function.audit_report
}

moved {
  from = aws_lambda_permission.monthly_audit
  to   = module.automation.aws_lambda_permission.monthly_audit
}

moved {
  from = aws_sns_topic.alerts
  to   = module.automation.aws_sns_topic.alerts
}

moved {
  from = aws_backup_plan.main
  to   = module.backup.aws_backup_plan.main
}

moved {
  from = aws_backup_selection.rds
  to   = module.backup.aws_backup_selection.rds
}

moved {
  from = aws_backup_vault.main
  to   = module.backup.aws_backup_vault.main
}

moved {
  from = aws_iam_role.backup
  to   = module.backup.aws_iam_role.backup
}

moved {
  from = aws_iam_role_policy_attachment.backup
  to   = module.backup.aws_iam_role_policy_attachment.backup
}

moved {
  from = aws_db_instance.postgres
  to   = module.data.aws_db_instance.postgres
}

moved {
  from = aws_db_subnet_group.main
  to   = module.data.aws_db_subnet_group.main
}

moved {
  from = aws_iam_instance_profile.app
  to   = module.iam.aws_iam_instance_profile.app
}

moved {
  from = aws_iam_role.app_instance
  to   = module.iam.aws_iam_role.app_instance
}

moved {
  from = aws_iam_role.auditor
  to   = module.iam.aws_iam_role.auditor
}

moved {
  from = aws_iam_role.operations_admin
  to   = module.iam.aws_iam_role.operations_admin
}

moved {
  from = aws_iam_role.security_admin
  to   = module.iam.aws_iam_role.security_admin
}

moved {
  from = aws_iam_role_policy.app_runtime
  to   = module.iam.aws_iam_role_policy.app_runtime
}

moved {
  from = aws_iam_role_policy.auditor_logs
  to   = module.iam.aws_iam_role_policy.auditor_logs
}

moved {
  from = aws_iam_role_policy_attachment.app_ssm
  to   = module.iam.aws_iam_role_policy_attachment.app_ssm
}

moved {
  from = aws_iam_role_policy_attachment.auditor_readonly
  to   = module.iam.aws_iam_role_policy_attachment.auditor_readonly
}

moved {
  from = aws_iam_role_policy_attachment.operations_readonly
  to   = module.iam.aws_iam_role_policy_attachment.operations_readonly
}

moved {
  from = aws_iam_role_policy_attachment.security_audit
  to   = module.iam.aws_iam_role_policy_attachment.security_audit
}

moved {
  from = aws_kms_alias.logs
  to   = module.kms.aws_kms_alias.logs
}

moved {
  from = aws_kms_alias.main
  to   = module.kms.aws_kms_alias.main
}

moved {
  from = aws_kms_key.logs
  to   = module.kms.aws_kms_key.logs
}

moved {
  from = aws_kms_key.main
  to   = module.kms.aws_kms_key.main
}

moved {
  from = aws_cloudtrail.main
  to   = module.logging.aws_cloudtrail.main
}

moved {
  from = aws_cloudwatch_log_group.cloudtrail
  to   = module.logging.aws_cloudwatch_log_group.cloudtrail
}

moved {
  from = aws_cloudwatch_log_group.vpc_flow
  to   = module.logging.aws_cloudwatch_log_group.vpc_flow
}

moved {
  from = aws_flow_log.vpc
  to   = module.logging.aws_flow_log.vpc
}

moved {
  from = aws_iam_role.cloudtrail_logs
  to   = module.logging.aws_iam_role.cloudtrail_logs
}

moved {
  from = aws_iam_role.vpc_flow_logs
  to   = module.logging.aws_iam_role.vpc_flow_logs
}

moved {
  from = aws_iam_role_policy.cloudtrail_logs
  to   = module.logging.aws_iam_role_policy.cloudtrail_logs
}

moved {
  from = aws_iam_role_policy.vpc_flow_logs
  to   = module.logging.aws_iam_role_policy.vpc_flow_logs
}

moved {
  from = aws_s3_bucket.central_logs
  to   = module.logging.aws_s3_bucket.central_logs
}

moved {
  from = aws_s3_bucket_object_lock_configuration.central_logs
  to   = module.logging.aws_s3_bucket_object_lock_configuration.central_logs
}

moved {
  from = aws_s3_bucket_policy.central_logs
  to   = module.logging.aws_s3_bucket_policy.central_logs
}

moved {
  from = aws_s3_bucket_public_access_block.central_logs
  to   = module.logging.aws_s3_bucket_public_access_block.central_logs
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.central_logs
  to   = module.logging.aws_s3_bucket_server_side_encryption_configuration.central_logs
}

moved {
  from = aws_s3_bucket_versioning.central_logs
  to   = module.logging.aws_s3_bucket_versioning.central_logs
}

moved {
  from = aws_eip.nat["a"]
  to   = module.network.aws_eip.nat["a"]
}

moved {
  from = aws_eip.nat["c"]
  to   = module.network.aws_eip.nat["c"]
}

moved {
  from = aws_internet_gateway.main
  to   = module.network.aws_internet_gateway.main
}

moved {
  from = aws_nat_gateway.main["a"]
  to   = module.network.aws_nat_gateway.main["a"]
}

moved {
  from = aws_nat_gateway.main["c"]
  to   = module.network.aws_nat_gateway.main["c"]
}

moved {
  from = aws_route_table.app["a"]
  to   = module.network.aws_route_table.app["a"]
}

moved {
  from = aws_route_table.app["c"]
  to   = module.network.aws_route_table.app["c"]
}

moved {
  from = aws_route_table.db
  to   = module.network.aws_route_table.db
}

moved {
  from = aws_route_table.public
  to   = module.network.aws_route_table.public
}

moved {
  from = aws_route_table_association.app["a"]
  to   = module.network.aws_route_table_association.app["a"]
}

moved {
  from = aws_route_table_association.app["c"]
  to   = module.network.aws_route_table_association.app["c"]
}

moved {
  from = aws_route_table_association.db["a"]
  to   = module.network.aws_route_table_association.db["a"]
}

moved {
  from = aws_route_table_association.db["c"]
  to   = module.network.aws_route_table_association.db["c"]
}

moved {
  from = aws_route_table_association.public["a"]
  to   = module.network.aws_route_table_association.public["a"]
}

moved {
  from = aws_route_table_association.public["c"]
  to   = module.network.aws_route_table_association.public["c"]
}

moved {
  from = aws_subnet.app["a"]
  to   = module.network.aws_subnet.app["a"]
}

moved {
  from = aws_subnet.app["c"]
  to   = module.network.aws_subnet.app["c"]
}

moved {
  from = aws_subnet.db["a"]
  to   = module.network.aws_subnet.db["a"]
}

moved {
  from = aws_subnet.db["c"]
  to   = module.network.aws_subnet.db["c"]
}

moved {
  from = aws_subnet.public["a"]
  to   = module.network.aws_subnet.public["a"]
}

moved {
  from = aws_subnet.public["c"]
  to   = module.network.aws_subnet.public["c"]
}

moved {
  from = aws_vpc.main
  to   = module.network.aws_vpc.main
}

moved {
  from = aws_vpc_endpoint.s3
  to   = module.network.aws_vpc_endpoint.s3
}

moved {
  from = aws_security_group.alb
  to   = module.security_groups.aws_security_group.alb
}

moved {
  from = aws_security_group.app
  to   = module.security_groups.aws_security_group.app
}

moved {
  from = aws_security_group.db
  to   = module.security_groups.aws_security_group.db
}

moved {
  from = aws_security_group.vpc_endpoints
  to   = module.security_groups.aws_security_group.vpc_endpoints
}

moved {
  from = aws_vpc_endpoint.interface["ec2messages"]
  to   = module.vpc_endpoints.aws_vpc_endpoint.interface["ec2messages"]
}

moved {
  from = aws_vpc_endpoint.interface["kms"]
  to   = module.vpc_endpoints.aws_vpc_endpoint.interface["kms"]
}

moved {
  from = aws_vpc_endpoint.interface["logs"]
  to   = module.vpc_endpoints.aws_vpc_endpoint.interface["logs"]
}

moved {
  from = aws_vpc_endpoint.interface["secretsmanager"]
  to   = module.vpc_endpoints.aws_vpc_endpoint.interface["secretsmanager"]
}

moved {
  from = aws_vpc_endpoint.interface["ssm"]
  to   = module.vpc_endpoints.aws_vpc_endpoint.interface["ssm"]
}

moved {
  from = aws_vpc_endpoint.interface["ssmmessages"]
  to   = module.vpc_endpoints.aws_vpc_endpoint.interface["ssmmessages"]
}

moved {
  from = aws_wafv2_web_acl.alb
  to   = module.waf.aws_wafv2_web_acl.alb
}

moved {
  from = aws_wafv2_web_acl_association.alb
  to   = module.waf.aws_wafv2_web_acl_association.alb
}

