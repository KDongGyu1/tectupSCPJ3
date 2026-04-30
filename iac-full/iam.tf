resource "aws_iam_role" "app_instance" {
  name = "${local.name_prefix}-app-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "app_runtime" {
  name = "${local.name_prefix}-app-runtime-policy"
  role = aws_iam_role.app_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "UseAppKmsKeys"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = [
          aws_kms_key.main.arn,
          aws_kms_key.logs.arn
        ]
      },
      {
        Sid    = "ReadRdsMasterSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_db_instance.postgres.master_user_secret[0].secret_arn
        ]
      },
      {
        Sid    = "WriteApplicationLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [for log_group in aws_cloudwatch_log_group.app : "${log_group.arn}:*"]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "${local.name_prefix}-app-instance-profile"
  role = aws_iam_role.app_instance.name
}

resource "aws_iam_role" "operations_admin" {
  name = "${local.name_prefix}-operations-admin-role"

  assume_role_policy = data.aws_iam_policy_document.assume_operations_admin.json
}

resource "aws_iam_role" "security_admin" {
  name = "${local.name_prefix}-security-admin-role"

  assume_role_policy = data.aws_iam_policy_document.assume_security_admin.json
}

resource "aws_iam_role" "auditor" {
  name = "${local.name_prefix}-auditor-readonly-role"

  assume_role_policy = data.aws_iam_policy_document.assume_auditor.json
}

resource "aws_iam_role" "developer" {
  name = "${local.name_prefix}-developer-role"

  assume_role_policy = data.aws_iam_policy_document.assume_developer.json
}

resource "aws_iam_role_policy" "operations_limited" {
  name = "${local.name_prefix}-operations-limited-policy"
  role = aws_iam_role.operations_admin.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeOperationalResources"
        Effect = "Allow"
        Action = [
          "autoscaling:Describe*",
          "ec2:DescribeInstances",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "elasticloadbalancing:Describe*",
          "rds:DescribeDBInstances",
          "rds:DescribeDBSubnetGroups",
          "wafv2:GetWebACL",
          "wafv2:ListResourcesForWebACL",
          "wafv2:ListWebACLs"
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadOperationalLogs"
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = concat(
          [for log_group in aws_cloudwatch_log_group.app : "${log_group.arn}:*"],
          [
            "${aws_cloudwatch_log_group.vpc_flow.arn}:*",
            "${aws_cloudwatch_log_group.cloudtrail.arn}:*",
            "${aws_cloudwatch_log_group.audit_report.arn}:*"
          ]
        )
      },
      {
        Sid      = "ListOperationalLogGroups"
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "security_admin_limited" {
  name = "${local.name_prefix}-security-admin-limited-policy"
  role = aws_iam_role.security_admin.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeSecurityBoundary"
        Effect = "Allow"
        Action = [
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSecurityGroupRules",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "wafv2:GetWebACL",
          "wafv2:ListResourcesForWebACL",
          "wafv2:ListWebACLs",
          "cloudtrail:LookupEvents"
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageProjectSecurityGroups"
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
          "ec2:UpdateSecurityGroupRuleDescriptionsEgress"
        ]
        Resource = [
          aws_security_group.alb.arn,
          aws_security_group.app.arn,
          aws_security_group.db.arn,
          aws_security_group.vpc_endpoints.arn
        ]
      },
      {
        Sid      = "UpdateProjectWaf"
        Effect   = "Allow"
        Action   = ["wafv2:UpdateWebACL"]
        Resource = aws_wafv2_web_acl.alb.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "auditor_logs" {
  name = "${local.name_prefix}-auditor-logs-policy"
  role = aws_iam_role.auditor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "LookupCloudTrailEvents"
        Effect   = "Allow"
        Action   = ["cloudtrail:LookupEvents"]
        Resource = "*"
      },
      {
        Sid    = "ReadAuditLogGroups"
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.cloudtrail.arn}:*",
          "${aws_cloudwatch_log_group.vpc_flow.arn}:*",
          "${aws_cloudwatch_log_group.audit_report.arn}:*"
        ]
      },
      {
        Sid      = "ListLogGroups"
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = "*"
      },
      {
        Sid    = "ReadCentralLogBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.central_logs.arn,
          "${aws_s3_bucket.central_logs.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "developer_readonly" {
  name = "${local.name_prefix}-developer-readonly-policy"
  role = aws_iam_role.developer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeRuntimeInfrastructure"
        Effect = "Allow"
        Action = [
          "autoscaling:Describe*",
          "ec2:Describe*",
          "elasticloadbalancing:Describe*",
          "wafv2:GetWebACL",
          "wafv2:ListResourcesForWebACL",
          "wafv2:ListWebACLs",
          "rds:DescribeDBInstances",
          "rds:DescribeDBSubnetGroups"
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadApplicationLogs"
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = concat(
          [for log_group in aws_cloudwatch_log_group.app : "${log_group.arn}:*"],
          ["${aws_cloudwatch_log_group.audit_report.arn}:*"]
        )
      },
      {
        Sid      = "ListLogGroups"
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = "*"
      }
    ]
  })
}
