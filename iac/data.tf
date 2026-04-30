resource "aws_db_subnet_group" "private" {
  count      = var.create_rds ? 1 : 0
  name       = "${local.name_prefix}-db-subnets"
  subnet_ids = var.private_subnet_ids
}

resource "aws_db_instance" "postgres" {
  count = var.create_rds ? 1 : 0

  identifier              = "${local.name_prefix}-postgres"
  engine                  = "postgres"
  engine_version          = "16.3"
  instance_class          = "db.t4g.micro"
  allocated_storage       = 20
  max_allocated_storage   = 100
  storage_encrypted       = true
  kms_key_id              = aws_kms_key.app.arn
  db_name                 = var.db_name
  username                = var.db_username
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.private[0].name
  vpc_security_group_ids  = [aws_security_group.data.id]
  backup_retention_period = 35
  deletion_protection     = true
  skip_final_snapshot     = false
  publicly_accessible     = false
  multi_az                = false

  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.app.arn
}

resource "aws_elasticache_subnet_group" "private" {
  count      = var.create_redis ? 1 : 0
  name       = "${local.name_prefix}-redis-subnets"
  subnet_ids = var.private_subnet_ids
}

resource "aws_elasticache_replication_group" "redis" {
  count = var.create_redis ? 1 : 0

  replication_group_id       = "${local.name_prefix}-redis"
  description                = "JWT/session Redis cache for ${local.name_prefix}"
  engine                     = "redis"
  node_type                  = "cache.t4g.micro"
  num_cache_clusters         = 1
  port                       = 6379
  subnet_group_name          = aws_elasticache_subnet_group.private[0].name
  security_group_ids         = [aws_security_group.data.id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  kms_key_id                 = aws_kms_key.app.arn
}
