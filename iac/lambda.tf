data "archive_file" "lambda" {
  for_each    = local.lambda_services
  type        = "zip"
  source_file = "${path.module}/lambda_src/${each.key}.js"
  output_path = "${path.module}/.terraform-build/${each.key}.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  for_each          = local.lambda_services
  name              = "/aws/lambda/${local.name_prefix}-${each.key}"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.audit.arn
}

resource "aws_lambda_function" "service" {
  for_each = local.lambda_services

  function_name    = "${local.name_prefix}-${each.key}"
  description      = each.value.description
  role             = aws_iam_role.lambda.arn
  handler          = each.value.handler
  runtime          = "nodejs20.x"
  filename         = data.archive_file.lambda[each.key].output_path
  source_code_hash = data.archive_file.lambda[each.key].output_base64sha256
  timeout          = 20
  memory_size      = 256
  kms_key_arn      = aws_kms_key.app.arn

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      PROJECT_NAME      = var.project_name
      ENVIRONMENT       = var.environment
      REGULATION_SCOPE  = each.value.regulation
      EVENT_QUEUE_URL   = aws_sqs_queue.events.url
      AUDIT_BUCKET_NAME = aws_s3_bucket.audit_worm.bucket
      ALERT_TOPIC_ARN   = aws_sns_topic.alerts.arn
      KMS_KEY_ID        = aws_kms_key.app.key_id
      USER_POOL_ID      = aws_cognito_user_pool.main.id
      PG_ENDPOINT_URL   = var.pg_endpoint_url
      BANK_ENDPOINT_URL = var.bank_endpoint_url
      FIU_ENDPOINT_URL  = var.fiu_endpoint_url
      DISPUTE_URL       = var.dispute_endpoint_url
      DB_ENDPOINT       = var.create_rds ? aws_db_instance.postgres[0].address : ""
      REDIS_ENDPOINT    = var.create_redis ? aws_elasticache_replication_group.redis[0].primary_endpoint_address : ""
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
}
