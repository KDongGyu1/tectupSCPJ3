locals {
  human_iam_users = {
    admin = {
      group = "admin"
    }
    developer = {
      group = "developer"
    }
    operator = {
      group = "operator"
    }
    auditor = {
      group = "auditor"
    }
  }
}

resource "aws_iam_user" "human" {
  for_each = local.human_iam_users

  name          = "${local.name_prefix}-${each.key}"
  force_destroy = false

  tags = {
    AccessType = "human"
    RoleModel  = "user-group-assume-role"
  }
}

resource "aws_iam_group" "human" {
  for_each = toset(["admin", "developer", "operator", "auditor"])

  name = "${local.name_prefix}-${each.key}-group"
}

resource "aws_iam_group_membership" "human" {
  for_each = local.human_iam_users

  name  = "${local.name_prefix}-${each.key}-membership"
  group = aws_iam_group.human[each.value.group].name
  users = [aws_iam_user.human[each.key].name]
}

data "aws_iam_policy_document" "assume_operations_admin" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "AWS"
      identifiers = [
        aws_iam_user.human["admin"].arn,
        aws_iam_user.human["operator"].arn
      ]
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

data "aws_iam_policy_document" "assume_security_admin" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_user.human["admin"].arn]
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

data "aws_iam_policy_document" "assume_developer" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_user.human["developer"].arn]
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

data "aws_iam_policy_document" "assume_auditor" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_user.human["auditor"].arn]
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

data "aws_iam_policy_document" "group_assume_admin" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole"
    ]
    resources = [
      aws_iam_role.operations_admin.arn,
      aws_iam_role.security_admin.arn
    ]
  }
}

data "aws_iam_policy_document" "group_assume_developer" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.developer.arn]
  }
}

data "aws_iam_policy_document" "group_assume_operator" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.operations_admin.arn]
  }
}

data "aws_iam_policy_document" "group_assume_auditor" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.auditor.arn]
  }
}

resource "aws_iam_group_policy" "assume_admin" {
  name   = "${local.name_prefix}-admin-assume-role-policy"
  group  = aws_iam_group.human["admin"].name
  policy = data.aws_iam_policy_document.group_assume_admin.json
}

resource "aws_iam_group_policy" "assume_developer" {
  name   = "${local.name_prefix}-developer-assume-role-policy"
  group  = aws_iam_group.human["developer"].name
  policy = data.aws_iam_policy_document.group_assume_developer.json
}

resource "aws_iam_group_policy" "assume_operator" {
  name   = "${local.name_prefix}-operator-assume-role-policy"
  group  = aws_iam_group.human["operator"].name
  policy = data.aws_iam_policy_document.group_assume_operator.json
}

resource "aws_iam_group_policy" "assume_auditor" {
  name   = "${local.name_prefix}-auditor-assume-role-policy"
  group  = aws_iam_group.human["auditor"].name
  policy = data.aws_iam_policy_document.group_assume_auditor.json
}
