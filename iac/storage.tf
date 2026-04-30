resource "aws_s3_bucket" "audit_worm" {
  bucket              = "${local.name_prefix}-audit-worm-${data.aws_caller_identity.current.account_id}"
  object_lock_enabled = true
}

resource "aws_s3_bucket_versioning" "audit_worm" {
  bucket = aws_s3_bucket.audit_worm.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit_worm" {
  bucket = aws_s3_bucket.audit_worm.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.audit.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_object_lock_configuration" "audit_worm" {
  bucket = aws_s3_bucket.audit_worm.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 2555
    }
  }
}

resource "aws_s3_bucket_public_access_block" "audit_worm" {
  bucket                  = aws_s3_bucket.audit_worm.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
