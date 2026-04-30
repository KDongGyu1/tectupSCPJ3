resource "aws_sqs_queue" "events_dlq" {
  name                              = "${local.name_prefix}-events-dlq"
  kms_master_key_id                 = aws_kms_key.app.arn
  message_retention_seconds         = 1209600
  kms_data_key_reuse_period_seconds = 300
}

resource "aws_sqs_queue" "events" {
  name                              = "${local.name_prefix}-events"
  kms_master_key_id                 = aws_kms_key.app.arn
  kms_data_key_reuse_period_seconds = 300
  visibility_timeout_seconds        = 60

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.events_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sns_topic" "alerts" {
  name              = "${local.name_prefix}-compliance-alerts"
  kms_master_key_id = aws_kms_key.audit.arn
}

resource "aws_sns_topic_subscription" "alert_email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
