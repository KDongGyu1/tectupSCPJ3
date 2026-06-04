data "aws_region" "current" {}

locals {
  endpoint_policy_actions = {
    kms = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
    ]
    secretsmanager = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]
    logs = [
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    ssm = [
      "ssm:DescribeAssociation",
      "ssm:GetDeployablePatchSnapshotForInstance",
      "ssm:GetDocument",
      "ssm:GetManifest",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:ListAssociations",
      "ssm:PutComplianceItems",
      "ssm:PutConfigurePackageResult",
      "ssm:PutInventory",
      "ssm:UpdateAssociationStatus",
      "ssm:UpdateInstanceAssociationStatus",
      "ssm:UpdateInstanceInformation",
    ]
    ssmmessages = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    ec2messages = [
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply",
    ]
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset([
    "kms",
    "secretsmanager",
    "logs",
    "ssm",
    "ssmmessages",
    "ec2messages",
  ])

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.app_subnet_ids
  security_group_ids  = [var.vpc_endpoint_sg_id]
  private_dns_enabled = true
  policy = var.enable_endpoint_policy_restrictions ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowRequiredEndpointActions"
        Effect    = "Allow"
        Principal = "*"
        Action    = local.endpoint_policy_actions[each.key]
        Resource  = "*"
      }
    ]
  }) : null

  tags = { Name = "${var.name_prefix}-${each.key}-endpoint" }
}
