

module "kms" {
  source      = "./modules/kms"
  name_prefix = local.name_prefix
}

module "network" {
  source = "./modules/network"

  name_prefix         = local.name_prefix
  vpc_cidr            = var.vpc_cidr
  az_names            = var.az_names
  public_subnet_cidrs = var.public_subnet_cidrs
  app_subnet_cidrs    = var.app_subnet_cidrs
  db_subnet_cidrs     = var.db_subnet_cidrs
}

module "security_groups" {
  source = "./modules/security_groups"

  name_prefix              = local.name_prefix
  vpc_id                   = module.network.vpc_id
  vpc_cidr                 = module.network.vpc_cidr
  allowed_http_cidr_blocks = var.allowed_http_cidr_blocks
}

module "vpc_endpoints" {
  source = "./modules/vpc_endpoints"

  name_prefix        = local.name_prefix
  vpc_id             = module.network.vpc_id
  app_subnet_ids     = module.network.app_subnet_ids
  vpc_endpoint_sg_id = module.security_groups.vpc_endpoint_sg_id
}

module "iam" {
  source = "./modules/iam"

  name_prefix = local.name_prefix
  account_id  = data.aws_caller_identity.current.account_id
}

module "logging" {
  source = "./modules/logging"

  name_prefix                    = local.name_prefix
  account_id                     = data.aws_caller_identity.current.account_id
  vpc_id                         = module.network.vpc_id
  logs_kms_key_arn               = module.kms.logs_kms_key_arn
  log_object_lock_retention_days = var.log_object_lock_retention_days
}

module "app" {
  source = "./modules/app"

  name_prefix               = local.name_prefix
  environment               = var.environment
  vpc_id                    = module.network.vpc_id
  public_subnet_ids         = module.network.public_subnet_ids
  app_subnet_ids            = module.network.app_subnet_ids
  alb_sg_id                 = module.security_groups.alb_sg_id
  app_sg_id                 = module.security_groups.app_sg_id
  app_instance_profile_name = module.iam.app_instance_profile_name
  logs_kms_key_arn          = module.kms.logs_kms_key_arn
  central_logs_bucket       = module.logging.central_logs_bucket
  enable_alb_access_logs    = var.enable_alb_access_logs
  alb_certificate_arn       = var.alb_certificate_arn
  app_instance_type         = var.app_instance_type
  app_desired_capacity      = var.app_desired_capacity
  app_min_size              = var.app_min_size
  app_max_size              = var.app_max_size

  depends_on = [module.logging]
}

module "data" {
  source = "./modules/data"

  name_prefix                 = local.name_prefix
  db_subnet_ids               = module.network.db_subnet_ids
  db_sg_id                    = module.security_groups.db_sg_id
  main_kms_key_arn            = module.kms.main_kms_key_arn
  db_instance_class           = var.db_instance_class
  db_name                     = var.db_name
  rds_backup_retention_period = var.rds_backup_retention_period
}

module "auth" {
  source      = "./modules/auth"
  name_prefix = local.name_prefix
}

module "waf" {
  source = "./modules/waf"

  name_prefix = local.name_prefix
  alb_arn     = module.app.alb_arn
}

module "backup" {
  source = "./modules/backup"

  name_prefix      = local.name_prefix
  main_kms_key_arn = module.kms.main_kms_key_arn
  rds_arn          = module.data.rds_arn
}

module "compliance" {
  source = "./modules/compliance"

  name_prefix         = local.name_prefix
  aws_region          = var.aws_region
  central_logs_bucket = module.logging.central_logs_bucket
  logs_kms_key_arn    = module.kms.logs_kms_key_arn
  enable_guardduty    = var.enable_guardduty
  enable_securityhub  = var.enable_securityhub
  enable_aws_config   = var.enable_aws_config

  depends_on = [module.logging]
}

module "automation" {
  source = "./modules/automation"

  name_prefix      = local.name_prefix
  project_name     = var.project_name
  environment      = var.environment
  alert_email      = var.alert_email
  logs_kms_key_arn = module.kms.logs_kms_key_arn
  alb_arn_suffix   = module.app.alb_arn_suffix
}
