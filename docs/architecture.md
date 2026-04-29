# Architecture Overview

The active Terraform entry point is the repository root.

## Layers

- Network: VPC, public subnets, private app subnets, isolated database subnets, gateways, route tables, and VPC endpoints.
- Edge: Public ALB with WAF attached.
- Application: Private EC2 Auto Scaling Groups for application services.
- Authentication: Cognito user pool and app client.
- Data: RDS PostgreSQL in isolated database subnets.
- Security and operations: KMS, IAM roles, CloudTrail, VPC Flow Logs, CloudWatch Logs, central S3 log storage, AWS Backup, and optional compliance services.

## Active Code

The modular Terraform structure under `modules/` is the source of truth.
