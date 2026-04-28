output "central_logs_bucket" { value = aws_s3_bucket.central_logs.bucket }
output "central_logs_bucket_id" { value = aws_s3_bucket.central_logs.id }
output "central_logs_bucket_arn" { value = aws_s3_bucket.central_logs.arn }
output "central_logs_bucket_policy_id" { value = aws_s3_bucket_policy.central_logs.id }
output "cloudtrail_arn" { value = aws_cloudtrail.main.arn }
