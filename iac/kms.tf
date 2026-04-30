resource "aws_kms_key" "app" {
  description             = "${local.name_prefix} application data encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "app" {
  name          = "alias/${local.name_prefix}-app"
  target_key_id = aws_kms_key.app.key_id
}

resource "aws_kms_key" "audit" {
  description             = "${local.name_prefix} audit and WORM evidence key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "audit" {
  name          = "alias/${local.name_prefix}-audit"
  target_key_id = aws_kms_key.audit.key_id
}
