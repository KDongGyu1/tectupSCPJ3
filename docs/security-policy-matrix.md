# Security Policy Matrix

| Area | Active module | Purpose |
| --- | --- | --- |
| Network isolation | `network`, `security_groups` | public, application, database tier를 분리한다. |
| Network compliance review | `security_groups`, `waf`, `vpc_endpoints` | external access control 위반 기준, inspection commands, response procedures를 정의한다. |
| Network change detection | `automation`, `logging` | CloudTrail EC2 API events에서 Security Group 변경을 탐지하고 SNS로 알림을 전송한다. |
| Private AWS access | `vpc_endpoints` | 지원되는 AWS services에 대해 public internet dependency를 줄인다. |
| Encryption | `kms`, `data`, `logging` | database, logs, related infrastructure data를 암호화한다. |
| Edge protection | `waf` | ALB traffic에 AWS managed rules와 path-specific rate limiting을 적용한다. |
| Identity | `iam`, `auth` | workload roles와 Cognito-based application authentication을 제공한다. |
| Logging | `logging` | CloudTrail, VPC Flow Logs, 활성화 시 ALB logs, CloudWatch logs를 중앙화한다. |
| Compliance monitoring | `compliance` | GuardDuty, Security Hub, AWS Config를 선택적으로 활성화한다. |
| Recovery | `backup` | RDS backup coverage를 관리한다. |
| Audit automation | `automation` | audit report generation과 SNS notification을 예약 실행한다. |

예상치 못한 비용이나 account subscription failures를 방지하기 위해 optional controls는 `terraform.tfvars.example`에서 기본 비활성화되어 있다.
