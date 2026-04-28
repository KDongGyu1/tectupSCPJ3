locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project      = var.project_name
    Environment  = var.environment
    ManagedBy    = "terraform"
    Architecture = "gpt-drawio-full-fintech-security"
  }

  az_map = {
    a = {
      az          = var.az_names[0]
      public_cidr = var.public_subnet_cidrs[0]
      app_cidr    = var.app_subnet_cidrs[0]
      db_cidr     = var.db_subnet_cidrs[0]
    }
    c = {
      az          = var.az_names[1]
      public_cidr = var.public_subnet_cidrs[1]
      app_cidr    = var.app_subnet_cidrs[1]
      db_cidr     = var.db_subnet_cidrs[1]
    }
  }

  app_services = {
    payment = {
      name        = "payment-api"
      path        = "/payments/*"
      description = "Payment API"
    }
    auth = {
      name        = "auth-user-api"
      path        = "/auth/*"
      description = "Auth and user API"
    }
    ops = {
      name        = "ops-audit-api"
      path        = "/ops/*"
      description = "Operations and audit API"
    }
  }

  rbac_groups = {
    Customer           = 70
    Merchant           = 60
    SettlementOperator = 50
    OperationsAdmin    = 40
    SecurityAdmin      = 30
    Auditor            = 20
  }
}

