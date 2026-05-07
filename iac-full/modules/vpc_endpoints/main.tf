data "aws_region" "current" {}

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

  tags = { Name = "${var.name_prefix}-${each.key}-endpoint" }
}
