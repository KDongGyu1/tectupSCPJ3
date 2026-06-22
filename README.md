# FinPay AWS Security Architecture

Terraform 기반의 **핀테크 결제 서비스 보안 아키텍처** 프로젝트입니다.  
이 저장소는 전자결제 서비스 환경에서 요구되는 네트워크 분리, 접근통제, 암호화, 감사 로그, 보안 이벤트 탐지, 백업, 규제 대응 기반을 AWS 인프라로 구현하는 것을 목표로 합니다.

## 1. 프로젝트 개요

FinPay는 고객, 가맹점, 운영자, 감사자 역할을 가진 결제 서비스 환경을 가정합니다.  
본 Terraform 코드는 애플리케이션이 안전하게 동작할 수 있도록 다음 보안 원칙을 인프라 수준에서 구현합니다.

- Public / App / DB 계층 분리
- 외부 진입점 CloudFront 및 ALB 계층화
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
CloudFront
   |
   v
AWS WAF (Regional Web ACL on ALB)
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

기본 배포에서는 WAF가 **ALB에 연결된 Regional Web ACL**로 동작합니다.  
CloudFront 커스텀 도메인과 Origin HTTPS를 활성화하면 사용자 트래픽은 `CloudFront -> ALB -> App -> RDS` 흐름을 따르며, ALB에 연결된 WAF가 Origin으로 들어오는 요청을 검사합니다.

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
| `enable_cloudfront_origin_only_alb_access` | `false` | ALB 직접 접근을 줄이기 위해 HTTPS 443을 CloudFront origin-facing prefix list에만 허용 |
| `enable_https_listener` | `false` | ACM 인증서가 있을 때 ALB HTTPS Listener 생성 |
| `enable_http_redirect` | `false` | HTTPS Listener가 있을 때 ALB HTTP 80을 HTTPS로 리다이렉트 |
| `enable_cloudfront_origin_https` | `false` | CloudFront에서 ALB Origin으로 HTTPS 사용 |
| `enable_alb_to_app_https` | `false` | ALB Target Group에서 App EC2 인스턴스로 HTTPS 사용 |
| `cloudfront_origin_domain_name` | `""` | CloudFront가 ALB Origin에 HTTPS로 접속할 때 사용할 Origin DNS 이름 |
| `cloudfront_aliases` | `[]` | CloudFront에 연결할 커스텀 도메인 목록 |
| `cloudfront_acm_certificate_arn` | `""` | CloudFront 커스텀 도메인에 사용할 us-east-1 ACM 인증서 ARN |
| `enable_cloudfront_viewer_mtls` | `false` | Client -> CloudFront 구간에서 Viewer mTLS 활성화 |
| `cloudfront_viewer_mtls_mode` | `"required"` | 클라이언트 인증서 요구 모드. `required` 또는 `optional` |
| `cloudfront_viewer_mtls_ca_bundle_path` | `"certs/mtls/finpay-ca-bundle.pem"` | CloudFront Trust Store에 업로드할 CA bundle 경로 |
| `enable_interface_endpoint_policy_restrictions` | `false` | Interface Endpoint 정책을 서비스별 허용 Action으로 제한 |

CloudFront 커스텀 도메인을 사용할 때는 Viewer용 인증서를 `us-east-1`에 생성해야 합니다. CloudFront -> ALB 구간을 HTTPS로 전환하는 경우 ALB 인증서의 도메인과 CloudFront Origin Domain Name이 일치해야 하므로, `origin.example.com` 같은 별도 CNAME을 ALB DNS 이름으로 연결한 뒤 `cloudfront_origin_domain_name`에 설정합니다.
ALB -> App 구간을 HTTPS로 전환하려면 `enable_alb_to_app_https = true`를 설정합니다. App 인스턴스는 부팅 시 로컬 서버 인증서를 생성하고 8080 포트에서 HTTPS로 요청을 받습니다.
Client -> CloudFront mTLS를 켜려면 현재 FinPay PKI CA bundle인 `certs/mtls/finpay-ca-bundle.pem`을 Trust Store에 업로드하고, 해당 CA가 발급한 클라이언트 인증서를 브라우저 또는 curl에 등록합니다. 로컬 테스트용 CA가 필요한 경우 `./scripts/generate-viewer-mtls-certs.sh`로 `certs/mtls/client-ca-bundle.pem`과 테스트 클라이언트 인증서를 생성할 수 있습니다.

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
├── certs/
│   └── mtls/
│       └── .gitkeep
├── scripts/
│   ├── cloudfront-viewer-mtls.sh
│   └── generate-viewer-mtls-certs.sh
├── bootstrap/
│   └── backend/
│       └── main.tf
├── docs/
│   ├── app-inspection-commands.md
│   ├── app-operations-compliance.md
│   ├── app-runtime-standards.md
│   ├── architecture.md
│   ├── iam-role-specification.md
│   ├── https-migration-owner-yunjeongwoo.md
│   ├── mtls-network-owner-yunjeongwoo.md
│   ├── network-access-control-compliance.md
│   ├── network-transport-security.md
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
| `docs/https-migration-owner-yunjeongwoo.md` | 윤정우 담당 CloudFront, ALB, ACM, DNS 기반 HTTPS 전환 설계와 증적 계획 |
| `docs/mtls-network-owner-yunjeongwoo.md` | 윤정우 담당 mTLS 적용 후보 구간, 통신 경로, SG/포트 영향 검토 |
| `docs/network-access-control-compliance.md` | Security Group, WAF, VPC Endpoint, ALB 우회 접근 점검 기준 |
| `docs/network-transport-security.md` | 네트워크 전송보안 구현 상태와 심화 개선 후보 |
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
aws sts get-caller-identity --profile LJH
```

다른 계정의 Role을 Assume하는 경우 `terraform.tfvars.example`을 참고해 로컬 전용 변수 파일을 만들고 다음 값을 설정할 수 있습니다. 실제 변수 파일은 계정 정보와 환경값이 들어갈 수 있으므로 Git에 커밋하지 않습니다.

```hcl
aws_profile              = "LJH"
assume_role_arn          = ""
assume_role_session_name = "finpay-terraform"
```

## 7. 사용 방법

### 1단계: 로컬 변수 파일 생성

```bash
cp terraform.tfvars.example terraform.tfvars
```

> `terraform.tfvars`는 로컬 실행용 파일입니다. Git에는 `terraform.tfvars.example`만 올리고, 실제 `terraform.tfvars`는 `.gitignore`로 제외합니다.

### 2단계: 로컬 변수 값 수정

예시:

```hcl
project_name = "finpay"
environment  = "dev"
aws_region   = "ap-northeast-2"


# 실제 CIDR, 이메일, 인증서 ARN, DB 설정은 로컬 terraform.tfvars에만 작성합니다.
# 저장소에는 terraform.tfvars.example만 커밋합니다.
```
실제 VPC CIDR, Subnet CIDR, alert_email, 인증서 ARN, DB 이름 등 환경별 값은
terraform.tfvars에만 작성하고 Git에는 커밋하지 않습니다.

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

### 7단계: App 코드 배포

`app/server.py`를 수정한 경우 Terraform apply만으로 실행 중인 EC2에 코드가 반영되지 않습니다.
App 인스턴스는 부팅 시 S3의 `tmp/server.py`를 내려받아 실행하므로, App 코드 변경 후에는 S3 업로드와 Auto Scaling instance refresh를 수행합니다.

```bash
./scripts/deploy-app.sh
```

기본값은 다음과 같습니다.

| 항목 | 기본값 |
| --- | --- |
| AWS Region | `ap-northeast-2` |
| Name Prefix | `finpay-dev` |
| App Artifact Bucket | `finpay-dev-tfstate-<account-id>` |
| App Artifact Key | `tmp/server.py` |
| 대상 ASG | `finpay-dev-payment-asg`, `finpay-dev-auth-asg`, `finpay-dev-ops-asg` |

다른 환경에 배포할 때는 환경변수로 덮어씁니다.

```bash
AWS_PROFILE=LJH \
AWS_REGION=ap-northeast-2 \
NAME_PREFIX=finpay-dev \
./scripts/deploy-app.sh
```

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
bucket       = "finpay-dev-tfstate-581586866411"
key          = "dev/terraform.tfstate"
region       = "ap-northeast-2"
profile      = "LJH"
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
| `cloudfront_distribution_id` | CloudFront Distribution ID |
| `cloudfront_distribution_domain_name` | CloudFront 기본 도메인 이름 |
| `cloudfront_viewer_mtls_enabled` | Client -> CloudFront Viewer mTLS 활성화 여부 |
| `cloudfront_viewer_mtls_trust_store_name` | CloudFront Viewer mTLS Trust Store 이름 |
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
  --profile LJH
```

### 테스트용 규칙 추가

먼저 ALB Security Group ID를 조회합니다.

```bash
ALB_SG_ID=$(aws ec2 describe-security-groups \
  --filters Name=group-name,Values=finpay-dev-alb-sg \
  --query "SecurityGroups[0].GroupId" \
  --output text \
  --region ap-northeast-2 \
  --profile LJH)
```

테스트용 인바운드 규칙을 추가합니다.

```bash
aws ec2 authorize-security-group-ingress \
  --group-id "$ALB_SG_ID" \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0 \
  --region ap-northeast-2 \
  --profile LJH
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
  --profile LJH
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
  --profile LJH
```

### SSH 공개 여부 확인

```bash
aws ec2 describe-security-groups \
  --query 'SecurityGroups[?IpPermissions[?FromPort==`22` && ToPort==`22`]].{GroupName:GroupName,GroupId:GroupId,Ingress:IpPermissions}' \
  --output table \
  --region ap-northeast-2 \
  --profile LJH
```

### Subnet Public IP 설정 확인

```bash
aws ec2 describe-subnets \
  --filters "Name=tag:Project,Values=finpay" \
  --query 'Subnets[*].{Name:Tags[?Key==`Name`]|[0].Value,SubnetId:SubnetId,AZ:AvailabilityZone,MapPublicIpOnLaunch:MapPublicIpOnLaunch,Cidr:CidrBlock}' \
  --output table \
  --region ap-northeast-2 \
  --profile LJH
```

### Route Table 확인

```bash
aws ec2 describe-route-tables \
  --filters "Name=tag:Project,Values=finpay" \
  --query 'RouteTables[*].{Name:Tags[?Key==`Name`]|[0].Value,RouteTableId:RouteTableId,Routes:Routes,Associations:Associations[*].SubnetId}' \
  --output json \
  --region ap-northeast-2 \
  --profile LJH
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
- CloudFront -> ALB Origin HTTPS 전환
- App -> RDS `sslmode=require` 이상 유지
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
