# Security Policy Matrix

| Area | Active module | Purpose |
| --- | --- | --- |
| Network isolation | `network`, `security_groups` | Separate public, application, and database tiers. |
| Private AWS access | `vpc_endpoints` | Reduce public internet dependency for supported AWS services. |
| Encryption | `kms`, `data`, `logging` | Encrypt database, logs, and related infrastructure data. |
| Edge protection | `waf` | Apply AWS managed rules and path-specific rate limiting to ALB traffic. |
| Identity | `iam`, `auth` | Provide workload roles and Cognito-based application authentication. |
| Logging | `logging` | Centralize CloudTrail, VPC Flow Logs, ALB logs when enabled, and CloudWatch logs. |
| Compliance monitoring | `compliance` | Optionally enable GuardDuty, Security Hub, and AWS Config. |
| Recovery | `backup` | Manage RDS backup coverage. |
| Audit automation | `automation` | Schedule audit report generation and SNS notification. |

Optional controls are disabled by default in `terraform.tfvars.example` to avoid unexpected cost or account subscription failures.
