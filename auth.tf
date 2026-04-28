resource "aws_cognito_user_pool" "main" {
  name = "${local.name_prefix}-app-users"

  mfa_configuration = "OPTIONAL"

  software_token_mfa_configuration {
    enabled = true
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  user_pool_add_ons {
    advanced_security_mode = "ENFORCED"
  }

  schema {
    name                = "role"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 1
      max_length = 64
    }
  }

  schema {
    name                = "merchant_id"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 1
      max_length = 64
    }
  }
}

resource "aws_cognito_user_pool_client" "web" {
  name                          = "${local.name_prefix}-web-client"
  user_pool_id                  = aws_cognito_user_pool.main.id
  generate_secret               = false
  prevent_user_existence_errors = "ENABLED"
  explicit_auth_flows           = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
}

resource "aws_cognito_user_group" "rbac" {
  for_each     = local.rbac_groups
  name         = each.key
  user_pool_id = aws_cognito_user_pool.main.id
  precedence   = each.value
}

