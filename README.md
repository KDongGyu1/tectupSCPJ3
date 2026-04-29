# FinPay AWS Security Architecture

FinPay AWS Security Architecture is a Terraform project for a secure fintech-style workload on AWS.

## Repository Layout

```text
.
├── main.tf                   # Module composition
├── variables.tf              # Input variables
├── terraform.tfvars.example  # Safe example values
├── modules/                  # Reusable Terraform modules
└── docs/                     # Architecture and security notes
```

Use the repository root for Terraform work.

## What It Builds

- VPC across two Seoul AZs: `ap-northeast-2a`, `ap-northeast-2c`
- Public, private app, and isolated database subnet tiers
- Internet Gateway, NAT Gateways, route tables, and VPC endpoints
- ALB, WAF, and private EC2 Auto Scaling Groups
- Cognito authentication with MFA-oriented configuration
- RDS PostgreSQL Multi-AZ with AWS-managed master secret
- KMS keys, Secrets Manager, CloudTrail, VPC Flow Logs, and CloudWatch Logs
- Central S3 log bucket with Object Lock retention
- Optional AWS Config, GuardDuty, and Security Hub controls
- AWS Backup plan and EventBridge/Lambda audit automation

## Quick Start

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
```

Run `terraform apply` only after reviewing cost and account limits.

## Cost And Account Notes

This stack can create billable AWS resources, especially NAT Gateways, EC2 Auto Scaling Groups, RDS, VPC endpoints, AWS Backup, and security services.

The example values keep expensive or account-sensitive options disabled by default:

```hcl
enable_guardduty           = false
enable_securityhub         = false
enable_aws_config          = false
enable_alb_access_logs     = false
rds_backup_retention_period = 1
```

Enable GuardDuty, Security Hub, AWS Config, and ALB access logs only after confirming the target AWS account supports the required service subscriptions, delivery policies, and KMS/S3 settings.

## Working Rules

- Do not commit `terraform.tfvars`, `*.tfstate`, plan files, or build artifacts.
- Add new Terraform resources through `modules/` when they belong to a reusable component.
- Update `docs/` when architecture, security controls, or operating assumptions change.
