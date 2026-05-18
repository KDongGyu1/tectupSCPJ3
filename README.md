# FinPay AWS Security Architecture

Terraform 기반의 **핀테크 결제 서비스 보안 아키텍처** 프로젝트입니다.  
이 저장소는 전자결제 서비스 환경에서 요구되는 네트워크 분리, 접근통제, 암호화, 감사 로그, 보안 이벤트 탐지, 백업, 규제 대응 기반을 AWS 인프라로 구현하는 것을 목표로 합니다.

## 1. 프로젝트 개요

FinPay는 고객, 가맹점, 운영자, 감사자 역할을 가진 결제 서비스 환경을 가정합니다.  
본 Terraform 코드는 애플리케이션이 안전하게 동작할 수 있도록 다음 보안 원칙을 인프라 수준에서 구현합니다.

- Public / App / DB 계층 분리
- 외부 진입점 ALB 단일화
- App 계층과 DB 계층의 직접 외부 노출 차단
- Security Group 기반 최소 접근 제어
- WAF를 통한 웹 공격 방어
- RDS PostgreSQL Multi-AZ 구성
- KMS 기반 저장 데이터 암호화
- Secrets Manager 기반 DB 마스터 비밀번호 관리
- CloudTrail, VPC Flow Logs, CloudWatch Logs 기반 감사 로그 수집
- EventBridge 기반 보안그룹 및 IAM 변경 탐지
- SNS 이메일 알림
- AWS Backup 기반 RDS 백업
- 선택적 GuardDuty, Security Hub, AWS Config 활성화

## 2. 전체 아키텍처

```text
Internet
   |
   v
AWS WAF
   |
   v
Public ALB
   |
   v
Private App Subnets
   |        ├─ payment-api
   |        ├─ auth-user-api
   |        └─ ops-audit-api
   |
   v
Isolated DB Subnets
   |
   v
RDS PostgreSQL Multi-AZ
```

보안 및 운영 계층은 다음과 같이 함께 구성됩니다.

```text
CloudTrail / VPC Flow Logs / CloudWatch Logs
        |
        v
Central S3 Log Bucket + KMS

EventBridge
        |
        v
SNS Alerts

AWS Backup
        |
        v
RDS Backup Vault
```

## 3. 주요 특징

### 네트워크 분리

- 하나의 VPC를 생성합니다.
- 2개의 Availability Zone을 사용합니다.
- 각 AZ마다 Public, App, DB 서브넷을 분리합니다.
- Public Subnet에는 ALB와 NAT Gateway를 배치합니다.
- App Subnet에는 EC2 Auto Scaling Group 기반 애플리케이션 인스턴스를 배치합니다.
- DB Subnet에는 RDS PostgreSQL을 배치합니다.
- DB Subnet은 인터넷으로 향하는 기본 경로를 갖지 않도록 설계되어 있습니다.

### 접근통제

Security Group은 계층별로 분리됩니다.

| Security Group | 주요 역할 | 허용되는 접근 |
| --- | --- | --- |
| ALB SG | 외부 진입점 | 지정된 CIDR에서 80/443 허용 |
| App SG | 애플리케이션 계층 | ALB SG에서 8080만 허용 |
| DB SG | 데이터베이스 계층 | App SG에서 5432만 허용 |
| VPC Endpoint SG | Interface Endpoint 접근 | App SG에서 443만 허용 |

### 웹 보안

ALB 앞단에 AWS WAF를 연결합니다.  
WAF에는 AWS Managed Rule과 서비스 경로별 Rate 기반 탐지 규칙이 포함됩니다.

적용되는 주요 Managed Rule은 다음과 같습니다.

- AWSManagedRulesAmazonIpReputationList
- AWSManagedRulesAnonymousIpList
- AWSManagedRulesCommonRuleSet
- AWSManagedRulesKnownBadInputsRuleSet
- AWSManagedRulesSQLiRuleSet
- AWSManagedRulesAdminProtectionRuleSet

서비스 경로별 Rate Rule은 다음 경로를 기준으로 구성됩니다.

- `/auth/`
- `/payments/`
- `/transactions/`
- `/ops/`
- `/audit/`

현재 Rate Rule은 차단보다 관찰과 검증을 우선하기 위해 `count` 동작으로 구성되어 있습니다.

### 인증 및 역할 관리

Cognito User Pool을 사용하여 애플리케이션 사용자 인증 기반을 구성합니다.

- MFA 구성: Optional
- Software Token MFA 활성화
- 강한 비밀번호 정책 적용
- Advanced Security Mode 적용
- 사용자 속성: `role`, `merchant_id`
- RBAC 그룹 구성

IAM 측면에서는 다음 역할을 구성합니다.

| IAM Role | 목적 |
| --- | --- |
| App Instance Role | EC2 애플리케이션 인스턴스 실행 권한 |
| Operations Admin Role | 운영자용 역할 |
| Security Admin Role | 보안 관리자용 역할 |
| Auditor Readonly Role | 감사자용 읽기 전용 역할 |

관리자성 역할의 AssumeRole 정책에는 MFA 조건이 포함됩니다.

### 데이터베이스

RDS PostgreSQL을 사용합니다.

- Engine: PostgreSQL
- Multi-AZ 활성화
- Publicly Accessible 비활성화
- Storage Encryption 활성화
- KMS Key 사용
- Secrets Manager를 통한 Master Password 관리
- IAM Database Authentication 활성화
- CloudWatch Logs Export 활성화
- Performance Insights 활성화

### 로깅 및 감사

중앙 로그 버킷과 CloudWatch Log Group을 구성합니다.

수집 대상은 다음과 같습니다.

- CloudTrail
- VPC Flow Logs
- CloudWatch Logs
- 선택적 ALB Access Logs

중앙 로그 S3 버킷에는 다음 보안 설정이 적용됩니다.

- S3 Versioning
- S3 Public Access Block
- KMS 기반 서버 측 암호화
- Object Lock 기능 사용 가능
- 선택적 기본 보존 기간 설정

개발 환경에서 반복적으로 `destroy`와 `apply`를 수행하는 경우 `enable_log_object_lock = false`를 유지하는 것을 권장합니다.  
기본 보존 기간을 활성화하면 로그 객체 삭제가 제한될 수 있습니다.

### 보안 이벤트 탐지

EventBridge를 통해 CloudTrail 기반 보안 이벤트를 감지합니다.

탐지 대상 예시는 다음과 같습니다.

#### Security Group 변경 탐지

- AuthorizeSecurityGroupIngress
- AuthorizeSecurityGroupEgress
- RevokeSecurityGroupIngress
- RevokeSecurityGroupEgress
- CreateSecurityGroup
- DeleteSecurityGroup
- ModifySecurityGroupRules
- UpdateSecurityGroupRuleDescriptionsIngress
- UpdateSecurityGroupRuleDescriptionsEgress

#### 고위험 IAM 변경 탐지

- CreateUser
- DeleteUser
- CreateAccessKey
- DeleteAccessKey
- AttachUserPolicy
- AttachRolePolicy
- PutUserPolicy
- PutRolePolicy
- UpdateAssumeRolePolicy
- CreatePolicyVersion
- SetDefaultPolicyVersion

탐지된 이벤트는 SNS Topic으로 전달되며, `alert_email`을 설정하면 이메일 알림을 받을 수 있습니다.

### 백업

AWS Backup을 사용하여 RDS 백업 계획을 구성합니다.

- Backup Vault 생성
- Daily RDS Backup Plan 생성
- RDS 인스턴스 Backup Selection 구성
- KMS 기반 Backup Vault 암호화

### 선택적 보안 서비스

비용과 계정 제한을 고려하여 일부 보안 서비스는 기본값이 비활성화되어 있습니다.

| 변수 | 기본값 | 설명 |
| --- | --- | --- |
| `enable_guardduty` | `false` | GuardDuty 활성화 여부 |
| `enable_securityhub` | `false` | Security Hub 활성화 여부 |
| `enable_aws_config` | `false` | AWS Config 및 Managed Rule 활성화 여부 |
| `enable_alb_access_logs` | `false` | ALB Access Log 활성화 여부 |
| `enable_log_object_lock` | `false` | S3 Object Lock 기본 보존 설정 활성화 여부 |

## 4. 디렉터리 구조

```text
.
├── main.tf
├── versions.tf
├── variables.tf
├── outputs.tf
├── locals.tf
├── moved.tf
├── backend-dev.hcl
├── terraform.tfvars.example
├── bootstrap/
│   └── backend/
│       └── main.tf
├── docs/
│   ├── app-inspection-commands.md
│   ├── app-operations-compliance.md
│   ├── app-runtime-standards.md
│   ├── architecture.md
│   ├── iam-role-specification.md
│   ├── network-access-control-compliance.md
│   ├── security-policy-matrix.md
│   ├── team-evidence-template.md
│   └── terraform-operations-runbook.md
└── modules/
    ├── app/
    ├── auth/
    ├── automation/
    ├── backup/
    ├── compliance/
    ├── data/
    ├── iam/
    ├── kms/
    ├── logging/
    ├── network/
    ├── security_groups/
    ├── vpc_endpoints/
    └── waf/
```

> `modules/app`은 Flask/Django 같은 애플리케이션 소스가 아니라, ALB, Target Group, Launch Template, Auto Scaling Group을 구성하는 Terraform 인프라 모듈입니다. 실제 애플리케이션 소스를 추가할 경우 Terraform 모듈과 섞이지 않도록 별도 `app/` 또는 `services/` 디렉터리를 사용하는 것을 권장합니다.

### 문서 파일 설명

| Document | 목적 |
| --- | --- |
| `docs/architecture.md` | 전체 AWS 보안 아키텍처와 네트워크 흐름 설명 |
| `docs/security-policy-matrix.md` | 역할, 권한, 보안 정책 매핑 |
| `docs/iam-role-specification.md` | IAM Role, AssumeRole, MFA 기반 접근 구조 설명 |
| `docs/network-access-control-compliance.md` | Security Group, WAF, VPC Endpoint, ALB 우회 접근 점검 기준 |
| `docs/app-runtime-standards.md` | App 서버 런타임, 포트, health check, 운영 기준 |
| `docs/app-inspection-commands.md` | App/ALB/EC2/CloudWatch 점검 명령어 모음 |
| `docs/app-operations-compliance.md` | App 운영 보안과 감사 대응 기준 |
| `docs/terraform-operations-runbook.md` | Terraform apply/destroy 운영 절차와 주의사항 |
| `docs/team-evidence-template.md` | 팀 프로젝트 증빙 캡처 및 제출 템플릿 |

## 5. 모듈 설명

| Module | 역할 |
| --- | --- |
| `network` | VPC, Subnet, IGW, NAT Gateway, Route Table, S3 Gateway Endpoint 구성 |
| `security_groups` | ALB, App, DB, VPC Endpoint Security Group 구성 |
| `vpc_endpoints` | KMS, Secrets Manager, Logs, SSM 계열 Interface Endpoint 구성 |
| `iam` | EC2 Instance Role, 운영자/보안관리자/감사자 Role 구성 |
| `kms` | 일반 암호화용 KMS Key와 로그 암호화용 KMS Key 구성 |
| `logging` | 중앙 로그 S3, CloudTrail, VPC Flow Logs, CloudWatch Logs 구성 |
| `app` | ALB, Target Group, Listener, Launch Template, Auto Scaling Group 구성 |
| `data` | RDS PostgreSQL Multi-AZ 구성 |
| `auth` | Cognito User Pool, Web Client, RBAC Group 구성 |
| `waf` | ALB용 AWS WAF Web ACL 및 Rule 구성 |
| `backup` | AWS Backup Vault, Plan, Selection 구성 |
| `compliance` | GuardDuty, Security Hub, AWS Config 선택적 구성 |
| `automation` | EventBridge, SNS, Lambda 기반 감사 자동화 및 보안 이벤트 알림 구성 |

## 6. 사전 준비

### 필수 도구

- Terraform 1.6 이상
- AWS CLI
- AWS 계정
- Terraform 실행 권한이 있는 IAM 사용자 또는 AssumeRole 권한

### AWS CLI 연결 확인

```bash
aws sts get-caller-identity
```

특정 profile을 사용하는 경우:

```bash
aws sts get-caller-identity --profile fintech
```

다른 계정의 Role을 Assume하는 경우 `terraform.tfvars`에 다음 값을 설정할 수 있습니다.

```hcl
aws_profile              = "fintech"
assume_role_arn          = "arn:aws:iam::123456789012:role/FintechTerraformRole"
assume_role_session_name = "finpay-terraform"
```

## 7. 사용 방법

### 1단계: 변수 파일 생성

```bash
cp terraform.tfvars.example terraform.tfvars
```

### 2단계: `terraform.tfvars` 수정

예시:

```hcl
project_name = "finpay"
environment  = "dev"
aws_region   = "ap-northeast-2"

aws_profile = "fintech"

vpc_cidr            = "10.0.0.0/16"
az_names            = ["ap-northeast-2a", "ap-northeast-2c"]
public_subnet_cidrs = ["10.0.0.0/24", "10.0.1.0/24"]
app_subnet_cidrs    = ["10.0.10.0/24", "10.0.11.0/24"]
db_subnet_cidrs     = ["10.0.20.0/24", "10.0.21.0/24"]

allowed_http_cidr_blocks = ["0.0.0.0/0"]
alb_certificate_arn      = ""

alert_email = "your-email@example.com"

app_instance_type    = "t3.micro"
app_desired_capacity = 1
app_min_size         = 1
app_max_size         = 2

db_instance_class = "db.t4g.micro"
db_name           = "finpay"

enable_guardduty       = false
enable_securityhub     = false
enable_aws_config      = false
enable_log_object_lock = false
```

### 3단계: 초기화

로컬 상태로 사용하는 경우:

```bash
terraform init
```

S3 Backend를 사용하는 경우:

```bash
terraform init -backend-config=backend-dev.hcl
```

### 4단계: 코드 검증

```bash
terraform fmt -recursive
terraform validate
```

### 5단계: Plan 확인

```bash
terraform plan
```

### 6단계: Apply

```bash
terraform apply
```

SNS 이메일 알림을 사용하는 경우, apply 이후 이메일로 도착하는 SNS 구독 확인 메일에서 **Confirm subscription**을 눌러야 실제 알림이 수신됩니다.

## 8. Backend Bootstrap

원격 Terraform State를 S3에 저장하려면 `bootstrap/backend`를 먼저 적용합니다.

```bash
cd bootstrap/backend
terraform init
terraform apply
```

그 후 루트 디렉터리로 돌아와 Backend를 초기화합니다.

```bash
cd ../..
terraform init -backend-config=backend-dev.hcl
```

`backend-dev.hcl` 예시:

```hcl
bucket       = "finpay-dev-tfstate-064137889010"
key          = "dev/terraform.tfstate"
region       = "ap-northeast-2"
profile      = "fintech"
encrypt      = true
use_lockfile = true
```

## 9. 주요 출력값

`terraform output`으로 다음 값을 확인할 수 있습니다.

| Output | 설명 |
| --- | --- |
| `vpc_id` | 생성된 VPC ID |
| `public_subnet_ids` | Public Subnet ID 목록 |
| `app_subnet_ids` | App Subnet ID 목록 |
| `db_subnet_ids` | DB Subnet ID 목록 |
| `alb_dns_name` | ALB DNS 이름 |
| `cognito_user_pool_id` | Cognito User Pool ID |
| `cognito_web_client_id` | Cognito Web Client ID |
| `rds_endpoint` | RDS Endpoint |
| `rds_master_secret_arn` | RDS Master Secret ARN |
| `central_logs_bucket` | 중앙 로그 S3 Bucket 이름 |
| `alerts_topic_arn` | 지역 보안 알림 SNS Topic ARN |
| `global_security_alerts_topic_arn` | 글로벌 보안 알림 SNS Topic ARN |
| `operations_admin_role_arn` | 운영자 Role ARN |
| `security_admin_role_arn` | 보안관리자 Role ARN |
| `auditor_role_arn` | 감사자 Role ARN |

## 10. 보안그룹 변경 탐지 테스트

보안그룹 변경 탐지 규칙은 EventBridge에서 Security Group 관련 EC2 API 호출을 감지하고 SNS로 알림을 전달합니다.

### EventBridge Rule 확인

```bash
aws events describe-rule \
  --name finpay-dev-security-group-changes \
  --region ap-northeast-2 \
  --profile fintech
```

### 테스트용 규칙 추가

먼저 ALB Security Group ID를 조회합니다.

```bash
ALB_SG_ID=$(aws ec2 describe-security-groups \
  --filters Name=group-name,Values=finpay-dev-alb-sg \
  --query "SecurityGroups[0].GroupId" \
  --output text \
  --region ap-northeast-2 \
  --profile fintech)
```

테스트용 인바운드 규칙을 추가합니다.

```bash
aws ec2 authorize-security-group-ingress \
  --group-id "$ALB_SG_ID" \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0 \
  --region ap-northeast-2 \
  --profile fintech
```

이 작업은 `AuthorizeSecurityGroupIngress` 이벤트를 발생시킵니다.

### 테스트 후 원상복구

```bash
aws ec2 revoke-security-group-ingress \
  --group-id "$ALB_SG_ID" \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0 \
  --region ap-northeast-2 \
  --profile fintech
```

이 작업은 `RevokeSecurityGroupIngress` 이벤트를 발생시킵니다.

## 11. 네트워크 접근통제 점검 명령어

### Security Group 확인

```bash
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=finpay-dev-alb-sg,finpay-dev-app-sg,finpay-dev-db-sg,finpay-dev-vpce-sg" \
  --query 'SecurityGroups[*].{GroupName:GroupName,GroupId:GroupId,Ingress:IpPermissions,Egress:IpPermissionsEgress}' \
  --output json \
  --region ap-northeast-2 \
  --profile fintech
```

### SSH 공개 여부 확인

```bash
aws ec2 describe-security-groups \
  --query 'SecurityGroups[?IpPermissions[?FromPort==`22` && ToPort==`22`]].{GroupName:GroupName,GroupId:GroupId,Ingress:IpPermissions}' \
  --output table \
  --region ap-northeast-2 \
  --profile fintech
```

### Subnet Public IP 설정 확인

```bash
aws ec2 describe-subnets \
  --filters "Name=tag:Project,Values=finpay" \
  --query 'Subnets[*].{Name:Tags[?Key==`Name`]|[0].Value,SubnetId:SubnetId,AZ:AvailabilityZone,MapPublicIpOnLaunch:MapPublicIpOnLaunch,Cidr:CidrBlock}' \
  --output table \
  --region ap-northeast-2 \
  --profile fintech
```

### Route Table 확인

```bash
aws ec2 describe-route-tables \
  --filters "Name=tag:Project,Values=finpay" \
  --query 'RouteTables[*].{Name:Tags[?Key==`Name`]|[0].Value,RouteTableId:RouteTableId,Routes:Routes,Associations:Associations[*].SubnetId}' \
  --output json \
  --region ap-northeast-2 \
  --profile fintech
```

## 12. 전자금융 보안 관점 매핑

| 보안 요구사항 | AWS 구현 |
| --- | --- |
| 내부망/외부망 분리 | Public / App / DB Subnet 분리 |
| 웹 서버와 DB 서버 분리 | ALB, App EC2, RDS 계층 분리 |
| 최소권한 원칙 | IAM Role 분리, Security Group source 제한 |
| 관리자 MFA | 운영자/보안관리자/감사자 Role Assume 시 MFA 조건 적용 |
| 저장 데이터 암호화 | KMS, RDS 암호화, S3 SSE-KMS |
| 전송 구간 보호 | HTTPS Listener 선택 구성, VPC Endpoint 사용 |
| 접속기록 및 감사 | CloudTrail, VPC Flow Logs, CloudWatch Logs |
| 보안 이벤트 탐지 | EventBridge + SNS |
| 백업 및 복구 | AWS Backup + RDS Backup Retention |

## 13. 비용 주의사항

이 프로젝트는 실제 과금이 발생할 수 있는 리소스를 생성합니다.

특히 다음 리소스는 비용이 발생할 수 있습니다.

- NAT Gateway
- EC2 Auto Scaling Group
- Application Load Balancer
- RDS Multi-AZ
- VPC Interface Endpoint
- AWS Backup
- CloudWatch Logs
- CloudTrail S3 저장 비용
- GuardDuty
- Security Hub
- AWS Config

실습 환경에서는 다음 값을 기본적으로 비활성화하거나 낮게 유지하는 것이 좋습니다.

```hcl
enable_guardduty            = false
enable_securityhub          = false
enable_aws_config           = false
enable_alb_access_logs      = false
enable_log_object_lock      = false
rds_backup_retention_period = 1
```

## 14. Destroy 주의사항

리소스를 삭제할 때는 다음 명령어를 사용합니다.

```bash
terraform destroy
```

주의할 점:

- Object Lock 기본 보존 설정을 켠 경우 S3 객체 삭제가 제한될 수 있습니다.
- RDS는 `skip_final_snapshot = true`, `deletion_protection = false`로 개발 환경 삭제가 가능하게 되어 있습니다.
- Backup Vault와 S3 Bucket은 개발 편의를 위해 `force_destroy`가 사용됩니다.
- 운영 환경에서는 `force_destroy`, `skip_final_snapshot`, `deletion_protection` 설정을 반드시 재검토해야 합니다.

## 15. 운영 환경 적용 전 개선 권장사항

현재 코드는 실습 및 발표용 보안 아키텍처에 적합하도록 구성되어 있습니다.  
운영 환경에 적용하기 전에는 다음 항목을 강화하는 것이 좋습니다.

- ALB HTTP 80을 HTTPS 443으로 리다이렉트
- ACM 인증서 연결
- Route 53 도메인 연결
- WAF Rate Rule을 `count`에서 `block`으로 단계적 전환
- `allowed_http_cidr_blocks` 범위 검토
- RDS deletion protection 활성화
- RDS final snapshot 활성화
- S3 `force_destroy` 비활성화
- Object Lock 보존 정책 운영 기준 확정
- Terraform backend bucket과 lock 설정 분리 관리
- CI/CD에서 `terraform fmt`, `validate`, `plan` 자동화
- Terraform apply 승인 절차 도입
- IAM 정책을 더 세분화하여 `Resource = "*"` 최소화

## 16. Git 관리 주의사항

다음 파일은 Git에 커밋하지 않습니다.

- `terraform.tfvars`
- `*.tfstate`
- `*.tfstate.backup`
- `.terraform/`
- `*.tfplan`
- 민감정보가 포함된 파일

`.gitignore` 정책을 확인하고, Access Key나 Secret Key가 저장소에 올라가지 않도록 주의해야 합니다.

## 17. 발표용 요약

이 프로젝트는 핀테크 결제 서비스를 가정하여 AWS 상에서 계층 분리형 보안 아키텍처를 Terraform으로 구현한 프로젝트입니다.  
외부 사용자는 WAF와 ALB를 통해서만 서비스에 접근하고, 애플리케이션 서버는 Private Subnet에 배치되며, 데이터베이스는 Isolated DB Subnet에 배치됩니다.  
Security Group은 ALB → App → DB 방향으로만 접근을 허용하여 직접 접근을 차단합니다.  
CloudTrail, VPC Flow Logs, CloudWatch Logs를 통해 감사 로그를 수집하고, EventBridge와 SNS를 통해 보안그룹 및 IAM 변경 이벤트를 탐지합니다.  
또한 KMS, Secrets Manager, RDS 암호화, AWS Backup, 선택적 GuardDuty/Security Hub/AWS Config를 통해 보안성과 규제 대응 가능성을 강화했습니다.
