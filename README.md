# FinPay Full AWS Security Architecture

This submission uses a modular Terraform layout. The `iac-full` directory is the root module, and each infrastructure domain is implemented under `modules/`.

```text
iac-full/
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
└── modules/
    ├── network/
    ├── security_groups/
    ├── vpc_endpoints/
    ├── kms/
    ├── iam/
    ├── logging/
    ├── app/
    ├── data/
    ├── auth/
    ├── waf/
    ├── backup/
    ├── compliance/
    └── automation/
```

This Terraform stack implements the `gpt draw.io.drawio` architecture end to end:

- VPC `10.0.0.0/16`
- 2 AZ design in Seoul: `ap-northeast-2a`, `ap-northeast-2c`
- Public, private app, and isolated DB subnet tiers
- Internet Gateway, one NAT Gateway per AZ, public/app/db route tables
- S3 Gateway endpoint plus interface endpoints for KMS, Secrets Manager, CloudWatch Logs, SSM, EC2 Messages, and SSM Messages
- ALB, WAF, and three private EC2 Auto Scaling Groups
- Cognito app user authentication with MFA and RBAC groups
- IAM human users and groups for `admin`, `developer`, `operator`, and `auditor`, with group policies that only allow `sts:AssumeRole` into scoped roles
- MFA-protected role trust policies with explicit IAM user principals
- RDS PostgreSQL Multi-AZ with AWS-managed master secret
- KMS CMKs, Secrets Manager, CloudTrail, VPC Flow Logs, CloudWatch Logs
- S3 central log bucket with Object Lock Compliance retention
- AWS Config, GuardDuty, Security Hub
- AWS Backup plan for RDS
- EventBridge real-time security monitoring, monthly audit report Lambda, and SNS email alerting

## Quick Start

```bash
cd iac-full
terraform init
terraform plan
terraform apply
```

The default plan creates real AWS resources that may incur cost, especially NAT Gateways, EC2 ASGs, RDS, and VPC endpoints.

For accounts with Free Tier or security service subscription limits, the default values keep the following optional controls disabled:

```hcl
enable_guardduty           = false
enable_securityhub         = false
enable_aws_config          = false
enable_alb_access_logs     = false
rds_backup_retention_period = 1
```

Turn GuardDuty, Security Hub, and AWS Config on only after your AWS account can subscribe to those services and deliver logs to the selected S3/KMS policy. ALB access logs are disabled by default because ALB log delivery can reject central buckets with stricter Object Lock/KMS settings; CloudTrail and VPC Flow Logs still remain enabled.

## Audit And Monitoring

The stack implements the phase 4 audit and monitoring baseline:

- CloudTrail multi-region management event logging with log file validation
- Central S3 log bucket with KMS encryption, versioning, public access block, and Object Lock retention
- VPC Flow Logs and application log groups encrypted with the log KMS key
- EventBridge detection rules for root account use, console login failures, unauthorized API calls, CloudTrail tampering, IAM policy changes, Security Group changes, and S3 public access changes
- SNS alert topic for EventBridge security events and CloudWatch alarms
- Scheduled monthly Lambda audit report

## IAM Access Model

Human access uses this pattern:

```text
IAM User -> IAM Group -> sts:AssumeRole -> Scoped IAM Role
```

Created users/groups:

- `admin`: can assume operations and security admin roles
- `developer`: can assume the developer read-only role
- `operator`: can assume the operations role
- `auditor`: can assume the auditor read-only role

The stack creates users without console passwords or access keys. Add credentials separately through your identity process, then require MFA before role assumption.

For HTTPS on the ALB, provide an ACM certificate ARN:

```bash
terraform apply -var='alb_certificate_arn=arn:aws:acm:ap-northeast-2:123456789012:certificate/xxxx'
```

Without `alb_certificate_arn`, the stack exposes HTTP port 80 so it remains deployable from scratch without a domain.
