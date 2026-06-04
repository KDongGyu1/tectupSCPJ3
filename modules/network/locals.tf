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

  s3_gateway_endpoint_policy_statements = length(var.s3_gateway_endpoint_bucket_arns) == 0 ? [
    {
      Sid       = "DenyS3EndpointUntilAllowedBucketsConfigured"
      Effect    = "Deny"
      Principal = "*"
      Action    = ["s3:*"]
      Resource  = ["*"]
    }
    ] : [
    {
      Sid       = "AllowConfiguredS3Buckets"
      Effect    = "Allow"
      Principal = "*"
      Action = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
      Resource = var.s3_gateway_endpoint_bucket_arns
    }
  ]
}
