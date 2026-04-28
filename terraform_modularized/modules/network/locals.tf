locals {
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
}
