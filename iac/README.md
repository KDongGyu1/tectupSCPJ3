# FinPay Compliance IaC

Terraform IaC for the final draw.io architecture:

- API Gateway + WAF
- Cognito User Pool with MFA and RBAC groups
- Lambda services for Auth helper, KYC, Payment, Query, Settlement, Audit, AML, Notification
- RDS PostgreSQL for transaction/user data
- ElastiCache Redis for JWT/session cache
- SQS event queue as the managed event backbone
- S3 Object Lock bucket for WORM audit evidence
- KMS keys for application data, audit logs, and object storage
- CloudTrail, CloudWatch Logs, EventBridge, SNS alerts

The VPC/network topology is intentionally external. Provide `vpc_id`, `private_subnet_ids`, and `public_subnet_ids` from your own network stack.

## Usage

```bash
cd iac
terraform init
terraform plan \
  -var='vpc_id=vpc-xxxxxxxx' \
  -var='private_subnet_ids=["subnet-aaa","subnet-bbb"]' \
  -var='public_subnet_ids=["subnet-ccc","subnet-ddd"]'
```

For a lower-cost demo, keep `create_rds=false` and `create_redis=false`. For a fuller regulated-shape environment, enable them through variables.
