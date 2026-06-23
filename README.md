# FinPay 심화 보안 고도화 프로젝트

> 전자금융 서비스 환경을 가정한 클라우드 보안 아키텍처 고도화 프로젝트

FinPay는 AWS 기반 결제 서비스를 가정한 보안 실습 프로젝트입니다. 기본 프로젝트에서는 VPC 계층 분리, App/DB Private Subnet, Security Group 최소 접근, WAF, Cognito, KMS, RDS, CloudTrail, VPC Flow Logs, CloudWatch Logs, EventBridge, SNS, AWS Backup을 구성했습니다.

심화 프로젝트에서는 이 기반 위에 전송보안, PKI/mTLS, App 보안 헤더, KMS/Secrets Manager 탐지, 민감 데이터 보호, 로그 보관, 운영 Runbook, 성능 검증을 추가로 고도화했습니다.

## 프로젝트 정보

| 항목 | 내용 |
| --- | --- |
| 프로젝트명 | FinPay 심화 보안 고도화 프로젝트 |
| 부제 | 암호학 기반 보안 솔루션 및 인증 체계 강화 |
| 팀명 | 구름수호대 |
| 대상 환경 | 전자금융 서비스를 가정한 AWS 클라우드 아키텍처 |
| IaC | Terraform |
| 주요 리전 | `ap-northeast-2`, CloudFront 인증서/전역 리소스는 조건에 따라 `us-east-1` |

## 팀원 역할

| 이름 | 역할 | 담당 범위 |
| --- | --- | --- |
| 김동규 | 팀장 / App·운영·성능 | App 보안 강화, Secure Cookie, HSTS, 성능 기준선, 산출물 취합 |
| 한경윤 | 감사·관제 | CloudTrail, EventBridge, SNS, 로그 증적, 위험 이벤트 탐지, Runbook |
| 임지혁 | 데이터보호 | KMS, RDS, Secrets Manager, 민감 데이터 분류, 컬럼 암호화 PoC |
| 윤정우 | 네트워크·접근통제 | CloudFront, ALB, WAF, SG, HTTPS 전환, PKI/mTLS PoC |

## 핵심 목표

- CloudFront, ALB, App, RDS로 이어지는 주요 통신 경로의 전송보안을 점검하고 강화합니다.
- HTTPS 전환 이후 App이 안전하게 동작하도록 Secure Cookie, HSTS, CSP 등 브라우저 보안 통제를 적용합니다.
- PKI 구조와 CloudFront Viewer mTLS PoC를 통해 인증서가 없는 클라이언트 접근 차단을 검증합니다.
- KMS, Secrets Manager, RDS, 민감 컬럼 암호화를 중심으로 데이터보호 체계를 정리합니다.
- CloudTrail, CloudWatch Logs, VPC Flow Logs, CloudFront Logs, EventBridge, SNS를 활용해 로그 수집·탐지·알림·대응 흐름을 구성합니다.
- 보안 적용 전후의 성능 기준선을 확보하고 전자금융 관련 규정 대응 항목과 매핑합니다.

## 전체 아키텍처

```text
User / Client
   |
   | HTTPS
   | Optional Viewer mTLS
   v
CloudFront
   |
   | HTTP or HTTPS, controlled by enable_cloudfront_origin_https
   v
Application Load Balancer
   |
   | HTTP 8080 by default
   | HTTPS optional with enable_alb_to_app_https
   v
EC2 Auto Scaling App
   |
   | PostgreSQL TLS, RDS_SSLMODE=require by default
   v
RDS PostgreSQL
```

운영 로그와 보안 이벤트 흐름은 다음과 같이 구성됩니다.

```text
CloudTrail / VPC Flow Logs / CloudWatch Logs / CloudFront Logs
        |
        v
S3 Log Bucket / CloudWatch Metrics
        |
        v
EventBridge Rules
        |
        v
SNS Email Alerts
        |
        v
Runbook 기반 확인, 조치, 재검증, 감사 기록
```

## 1~6단계 수행 요약

| 단계 | 주제 | 주요 결과 |
| --- | --- | --- |
| 1단계 | 보안 진단, 공격면 분석, 규정 매핑 | CloudFront -> ALB HTTP, ALB 직접 접근, App -> RDS TLS 확인 필요, WAF Count 모드 등 잔여 위험 식별 |
| 2단계 | HTTPS 기반 App 보안 강화 | HTTPS 환경 감지, Secure Cookie, HSTS 조건부 적용, CSP, `nosniff`, Referrer-Policy, Permissions-Policy 적용 |
| 3단계 | PKI/mTLS PoC | Client -> CloudFront Viewer mTLS 후보 선정, 인증서 미제출 요청 차단, CloudFront Connection Log 증적 확보 |
| 4단계 | KMS, RDS TLS, 민감 데이터 보호 | KMS/Secrets Manager 위험 이벤트 탐지, App -> RDS `sslmode=require`, 민감 데이터 분류, 컬럼 암호화 PoC 기준 수립 |
| 5단계 | 로그 보관 및 보안 관제 | CloudTrail, CloudWatch Logs, VPC Flow Logs, CloudFront Standard/Connection Logs, EventBridge, SNS, Runbook 정리 |
| 6단계 | 최종 보고 | 성능·비용·규정 매핑·역할별 산출물 통합, 발표 및 시연 시나리오 정리 |

## 심화 단계 산출물 반영 상세

README는 최종 보고서의 요약본 역할을 하며, 각 단계에서 다룬 산출물은 다음 범위로 반영했습니다.

| 단계 | 세부 산출물 | README 반영 위치 |
| --- | --- | --- |
| 1단계 | 보안 진단표, 네트워크/접근통제 진단표, 공격면 분석표, 전자금융감독규정 대응 매핑표 | 전체 목표, 1~6단계 수행 요약, 전자금융 관련 규정 대응 관점, 주요 문서 |
| 1단계 | 전송보안 개선 과제 목록, P1/P2/P3 우선순위 | 전송보안, Terraform 변수 요약, 향후 개선 과제 |
| 2단계 | HTTPS 전환 이후 App 보안 강화, Secure Cookie, HSTS, CSP, 보안 헤더 | App 보안, 검증 명령어, 시연 시나리오 |
| 2단계 | CloudFront -> ALB HTTPS, ALB HTTP -> HTTPS 리다이렉트, ACM/커스텀 도메인 검토 | 전송보안, Terraform 변수 요약, 향후 개선 과제 |
| 2단계 | 인증서 위험 시나리오, 인증서 만료 알림 및 갱신 실패 대응 | 인증서 및 도메인 운영 기준, 향후 개선 과제 |
| 3단계 | PKI 구조 초안, mTLS 후보 구간 검토, CloudFront Viewer mTLS PoC | PKI/mTLS PoC, 시연 시나리오 |
| 3단계 | 인증서 미제출 요청 차단, `Failed:ClientCertMissing`, Standard/Connection Log 증적 | PKI/mTLS PoC, 로그 보관 및 관제, 검증 명령어 |
| 3단계 | HTTPS 성능 기준선, CloudWatch `TargetResponseTime`, `RequestCount`, `5XX` 확인 | 성능 기준선, 운영 검증 포인트 |
| 4단계 | KMS/Secrets Manager 위험 이벤트 탐지, 키 삭제/비활성화/정책 변경/Secret 이벤트 | 데이터보호 및 키 관리, 로그 보관 및 관제 |
| 4단계 | DB 접근통제, App -> RDS TLS 검증, 민감 데이터 분류 | 데이터보호 및 키 관리, 전자금융 관련 규정 대응 관점 |
| 4단계 | 컬럼 단위 암호화 PoC, 암호화 방식 검토, 성능 비교 기준 | 암호 알고리즘 및 컬럼 암호화 PoC |
| 5단계 | CloudWatch Logs 운영 로그 평가, App 이벤트 대응 Runbook | 로그 보관 및 관제, 운영 Runbook |
| 5단계 | 취약 암호 알고리즘 점검표, 인증서·네트워크 로그 보관 기준서 | 암호 알고리즘 및 컬럼 암호화 PoC, 로그 보관 및 관제 |
| 5단계 | Security Hub, GuardDuty, AWS Config 확장 검토 | 로그 보관 및 관제, 향후 개선 과제, 주의 사항 |
| 6단계 | 성능 비교, 비용 분석, 규정 매핑 최종화, 최종 보고서/발표자료 | 성능 기준선, 비용 및 운영 영향, 전자금융 관련 규정 대응 관점 |
| 6단계 | 데이터보호 최종 결과표, 관제 최종 보고, 네트워크/전송보안 최종 보고 | 데이터보호 및 키 관리, 로그 보관 및 관제, 전송보안 |

## 주요 구현 및 검증 항목

### 전송보안

- CloudFront Viewer Protocol Policy는 HTTPS 리다이렉트 구조를 사용합니다.
- ALB HTTPS Listener는 `enable_https_listener`와 ACM 인증서가 있을 때 활성화할 수 있습니다.
- CloudFront -> ALB HTTPS 전환은 `enable_cloudfront_origin_https`로 제어합니다.
- ALB HTTP -> HTTPS 리다이렉트는 `enable_http_redirect`로 제어합니다.
- ALB -> App HTTPS는 `enable_alb_to_app_https`로 검토 가능한 선택 기능입니다.
- App -> RDS는 `rds_sslmode = "require"`를 기본값으로 사용해 PostgreSQL TLS 연결을 요구합니다.

### 인증서 및 도메인 운영 기준

- CloudFront 커스텀 도메인은 `cloudfront_aliases`와 `cloudfront_acm_certificate_arn`으로 구성합니다.
- CloudFront Viewer 인증서는 AWS 서비스 특성상 `us-east-1` ACM 인증서를 사용합니다.
- CloudFront -> ALB Origin HTTPS를 적용하려면 ALB 인증서의 SAN과 `cloudfront_origin_domain_name`이 일치해야 합니다.
- 인증서 만료, DNS 검증 실패, 갱신 실패는 운영 위험 시나리오로 분류하고 EventBridge/SNS 기반 만료 알림 고도화를 향후 과제로 둡니다.
- Route 53 기반 운영 도메인 구성은 도메인 비용과 검증 권한이 필요한 심화 개선 과제로 분리했습니다.

### App 보안

App 계층은 HTTPS 전환 이후 안전하게 동작하도록 다음 방어 기능을 포함합니다.

- `X-Forwarded-Proto=https` 또는 `APP_BASE_URL=https://...` 기반 HTTPS 환경 감지
- HTTPS 환경에서 `finpay_session` 쿠키에 `Secure` 자동 적용
- 로그인/로그아웃 쿠키 속성 일관화
  - `HttpOnly`
  - `SameSite=Lax`
  - `Secure`
  - `Path=/`
- 공통 보안 헤더 적용
  - `Content-Security-Policy`
  - `X-Content-Type-Options: nosniff`
  - `Referrer-Policy`
  - `Permissions-Policy`
  - `Strict-Transport-Security`

### PKI/mTLS PoC

이번 프로젝트의 mTLS PoC는 운영 진입점과 가장 잘 맞는 `Client -> CloudFront` 구간을 대상으로 검토했습니다.

```text
Client Certificate
  -> CloudFront Viewer mTLS
  -> CloudFront Trust Store
  -> ALB
  -> App
```

검증 결과:

- 인증서 없는 요청은 TLS Handshake 단계에서 차단됩니다.
- CloudFront Connection Log에서 `Failed:ClientCertMissing` 이벤트를 확인했습니다.
- 정상 요청은 CloudFront Standard Access Log에서 `/health` `200` 응답으로 확인했습니다.
- TLS 버전은 `TLSv1.3`, Cipher Suite는 `TLS_AES_128_GCM_SHA256`으로 확인했습니다.

테스트 인증서 생성:

```bash
./scripts/generate-viewer-mtls-certs.sh
```

mTLS 설정 보조 스크립트:

```bash
scripts/cloudfront-viewer-mtls.sh status
```

검증 예시:

```bash
curl -v https://app.finpay-sec.p-e.kr/health

curl -v \
  --cert certs/mtls/client.crt \
  --key certs/mtls/client.key \
  https://app.finpay-sec.p-e.kr/health
```

> 주의: 이 저장소에서는 CloudFront Viewer mTLS를 Terraform 변수와 보조 스크립트로 지원합니다. AWS provider 지원 범위에 따라 Trust Store 및 `ViewerMtlsConfig` 적용은 `scripts/cloudfront-viewer-mtls.sh`를 통해 보조 처리합니다.

### 데이터보호 및 키 관리

- RDS PostgreSQL은 저장 데이터 암호화와 Secrets Manager 기반 마스터 비밀번호 관리를 사용합니다.
- App -> RDS 연결은 `RDS_SSLMODE=require`를 통해 TLS 요구 옵션을 반영합니다.
- KMS 키 삭제, 비활성화, 정책 변경, Secrets Manager 관련 위험 이벤트를 EventBridge와 SNS 알림 흐름으로 탐지하도록 구성합니다.
- 민감 데이터 분류 후 컬럼 단위 암호화 PoC 대상을 선정했습니다.
- 취약 알고리즘 점검을 통해 MD5, SHA-1, DES 등 레거시 알고리즘 사용 여부와 교체 방향을 정리했습니다.

### 암호 알고리즘 및 컬럼 암호화 PoC

심화 프로젝트의 암호학 요구사항에 맞춰 다음 항목을 점검했습니다.

| 항목 | 반영 내용 |
| --- | --- |
| 취약 알고리즘 점검 | MD5, SHA-1, DES 등 레거시 알고리즘 사용 여부와 제거 방향 정리 |
| 권장 알고리즘 기준 | AES-256, SHA-256 이상, RSA-2048 이상, ECC 계열 사용 방향 정리 |
| 민감 데이터 분류 | 이름, 연락처, 결제정보 등 암호화 후보 필드 식별 |
| 암호화 적용 방식 검토 | KMS 기반 키 관리와 App 레벨 암호화·복호화 흐름 정의 |
| 성능 비교 기준 | 암호화 적용 전후 App 응답시간, 처리속도, CPU 부하 비교 기준 수립 |
| 키 생명주기 | 키 생성, 저장, 갱신, 폐기 절차와 위험 이벤트 탐지 연결 |

### 로그 보관 및 관제

수집·확인 대상:

- CloudTrail
- VPC Flow Logs
- CloudWatch Logs
- CloudFront Standard Access Logs
- CloudFront Connection Logs
- EventBridge 이벤트
- SNS 알림

이 프로젝트에서는 GuardDuty, Security Hub, AWS Config를 기본 활성화로 전제하지 않습니다. 비용, 계정 권한, 실습 환경 제약을 고려해 Terraform 변수로 선택 활성화할 수 있게 두었고, 최종 보고서에서는 향후 관제 고도화 후보로 분리했습니다.

| 항목 | 기본값 | 설명 |
| --- | --- | --- |
| `enable_guardduty` | `false` | GuardDuty 선택 활성화 |
| `enable_securityhub` | `false` | Security Hub 선택 활성화 |
| `enable_aws_config` | `false` | AWS Config Recorder 및 Managed Rule 선택 활성화 |

### 운영 Runbook

운영 대응은 다음 흐름으로 표준화했습니다.

```text
이벤트 발생
  -> 로그 확인
  -> 위험도 분류
  -> 담당자 확인
  -> 조치 실행
  -> 재검증
  -> 감사 기록 보관
```

Runbook 대상:

- mTLS 인증 실패 대응
- App 운영 이벤트 대응
- 인증서 및 네트워크 로그 보관
- KMS/Secrets Manager 위험 이벤트 대응
- Security Group 변경 탐지 및 알림 대응

## 성능 기준선

mTLS 적용 전 HTTPS 기준 `/health` 성능 기준선을 확보했습니다.

| 지표 | 결과 |
| --- | --- |
| 측정 대상 | `https://app.finpay-sec.p-e.kr/health` |
| 요청 수 | 30 |
| 2xx 성공 수 | 30 |
| 실패 수 | 0 |
| 실패율 | 0% |
| 평균 응답시간 | 0.076초 |
| p50 | 0.075초 |
| p95 | 0.087초 |
| 최소 | 0.057초 |
| 최대 | 0.110초 |

이 기준선은 mTLS, 컬럼 암호화, 전송보안 강화 이후의 성능 영향 비교 기준으로 사용합니다.

## 운영 검증 포인트

| 검증 항목 | 확인 기준 |
| --- | --- |
| App Health Check | `/health` 또는 `/api/health` 200 응답 |
| ALB Target 상태 | Target Group `healthy` |
| ASG 상태 | Instance `InService`, `Healthy` |
| CloudWatch 성능 지표 | `TargetResponseTime`, `RequestCount`, `HTTPCode_Target_5XX_Count` |
| mTLS 실패 증적 | CloudFront Connection Log의 `Failed:ClientCertMissing` |
| mTLS 정상 증적 | CloudFront Standard Access Log의 `/health` 200 응답 |
| 보안 헤더 | HSTS, CSP, `nosniff`, Referrer-Policy, Permissions-Policy |
| RDS TLS | App 연결 문자열 또는 환경변수의 `sslmode=require` |

## 비용 및 운영 영향

6단계에서는 보안 고도화 항목이 비용과 운영 복잡도에 미치는 영향을 함께 정리했습니다.

| 항목 | 비용/운영 영향 | 프로젝트 판단 |
| --- | --- | --- |
| CloudFront Standard/Connection Logs | S3 저장 비용 증가 | mTLS 증적 확보를 위해 필요 |
| ACM/커스텀 도메인 | 도메인 관리와 DNS 검증 필요 | 운영 도메인 적용 시 필수 |
| ALB -> App HTTPS/mTLS | 인증서 배포와 Health Check 운영 복잡도 증가 | 심화 개선 과제로 분리 |
| KMS/Secrets Manager | 키/비밀값 API 호출 및 관리 비용 | 데이터보호 핵심 항목으로 유지 |
| GuardDuty/Security Hub/AWS Config | 서비스 활성화 비용과 Findings 운영 부담 | 기본 비활성화, 향후 관제 확장 후보 |
| S3 Lifecycle/Object Lock | 보관 비용 및 삭제 제한 영향 | 운영 정책 확정 후 적용 |

## Terraform 변수 요약

| 변수 | 기본값 | 역할 |
| --- | --- | --- |
| `enable_https_listener` | `false` | ALB HTTPS Listener 생성 |
| `enable_http_redirect` | `false` | ALB HTTP 요청을 HTTPS로 리다이렉트 |
| `enable_cloudfront_origin_https` | `false` | CloudFront -> ALB Origin을 HTTPS로 전환 |
| `enable_alb_to_app_https` | `false` | ALB -> App Target Group을 HTTPS로 전환 |
| `enable_cloudfront_origin_only_alb_access` | `false` | ALB 접근을 CloudFront origin-facing prefix list로 제한 |
| `enable_cloudfront_standard_logs` | `true` | CloudFront Standard Access Log 저장 |
| `enable_cloudfront_connection_logs` | `false` | CloudFront Viewer mTLS Connection Log 저장 |
| `enable_cloudfront_viewer_mtls` | `false` | Client -> CloudFront Viewer mTLS 활성화 |
| `cloudfront_viewer_mtls_mode` | `"required"` | 클라이언트 인증서 요구 모드 |
| `rds_sslmode` | `"require"` | App -> RDS PostgreSQL TLS 요구 수준 |
| `waf_rate_rule_action` | `"count"` | WAF 경로별 Rate Rule 동작 |
| `enable_interface_endpoint_policy_restrictions` | `false` | Interface Endpoint 정책 제한 |

전체 변수는 [`variables.tf`](variables.tf)와 [`terraform.tfvars.example`](terraform.tfvars.example)를 참고합니다.

## 저장소 구조

```text
.
├── app/
│   ├── server.py
│   ├── column_crypto.py
│   ├── schema.sql
│   └── README.md
├── modules/
│   ├── app/
│   ├── automation/
│   ├── backup/
│   ├── compliance/
│   ├── data/
│   ├── iam/
│   ├── kms/
│   ├── logging/
│   ├── network/
│   ├── security_groups/
│   ├── vpc_endpoints/
│   └── waf/
├── scripts/
│   ├── cloudfront-viewer-mtls.sh
│   ├── deploy-app.sh
│   └── generate-viewer-mtls-certs.sh
├── docs/
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
└── terraform.tfvars.example
```

## 주요 문서

| 문서 | 설명 |
| --- | --- |
| [`attack-surface-analysis.md`](attack-surface-analysis.md) | 공격면 분석표 |
| [`network-access-control-diagnosis.md`](network-access-control-diagnosis.md) | 네트워크/접근통제 진단표 |
| [`transport-security-improvement-tasks.md`](transport-security-improvement-tasks.md) | 전송보안 개선 과제 목록 |
| [`docs/https-migration-owner-yunjeongwoo.md`](docs/https-migration-owner-yunjeongwoo.md) | HTTPS 전환 담당 산출물 |
| [`docs/mtls-network-owner-yunjeongwoo.md`](docs/mtls-network-owner-yunjeongwoo.md) | mTLS 적용 구간 검토 및 PoC 문서 |
| [`docs/network-transport-security.md`](docs/network-transport-security.md) | 네트워크 전송보안 기준 |
| [`docs/terraform-operations-runbook.md`](docs/terraform-operations-runbook.md) | Terraform 운영 Runbook |
| [`docs/team-evidence-template.md`](docs/team-evidence-template.md) | 팀 증적 정리 템플릿 |

## 배포 절차

### 1. Terraform 변수 준비

```bash
cp terraform.tfvars.example terraform.tfvars
```

필요한 값을 수정합니다.

```hcl
project_name = "finpay"
environment  = "dev"
aws_region   = "ap-northeast-2"
alert_email  = "security-team@example.com"
rds_sslmode  = "require"
```

### 2. 초기화

```bash
terraform init -reconfigure -backend-config=backend-dev.hcl
```

### 3. 계획 확인

```bash
terraform plan
```

### 4. 적용

```bash
terraform apply
```

### 5. 주요 출력 확인

```bash
terraform output
```

## 검증 명령어

### HTTPS 및 App 상태

```bash
curl -I https://app.finpay-sec.p-e.kr/
curl -i https://app.finpay-sec.p-e.kr/health
```

### 보안 헤더 확인

```bash
curl -I https://app.finpay-sec.p-e.kr/ | rg -i "strict-transport-security|content-security-policy|x-content-type-options|referrer-policy|permissions-policy|set-cookie"
```

### RDS TLS 코드 반영 확인

```bash
rg -n "RDS_SSLMODE|sslmode" app/server.py modules/app/user_data.sh.tftpl
```

### ALB Listener 및 Target Group 확인

```bash
aws elbv2 describe-listeners \
  --region ap-northeast-2 \
  --load-balancer-arn "$ALB_ARN"

aws elbv2 describe-target-groups \
  --region ap-northeast-2 \
  --load-balancer-arn "$ALB_ARN"
```

### CloudFront 설정 확인

```bash
aws cloudfront get-distribution-config \
  --id "$CLOUDFRONT_DISTRIBUTION_ID"
```

### CloudFront 로그 확인

```bash
aws s3 ls s3://finpay-dev-cloudfront-logs-233338945536/standard/ --recursive
aws s3 ls s3://finpay-dev-cloudfront-logs-233338945536/AWSLogs/233338945536/connection/ --recursive
```

### EventBridge 및 SNS 확인

```bash
aws events describe-rule --name "$RULE_NAME" --region ap-northeast-2
aws events list-targets-by-rule --rule "$RULE_NAME" --region ap-northeast-2
aws sns list-subscriptions --region ap-northeast-2
```

## 시연 시나리오

발표 시연은 다음 흐름을 권장합니다.

1. 정상 HTTPS `/health` 요청 성공 확인
2. 클라이언트 인증서 없는 mTLS 요청 실패 확인
3. CloudFront Connection Log에서 `Failed:ClientCertMissing` 확인
4. CloudFront Standard Access Log에서 정상 요청 `200` 확인
5. `curl -I`로 Secure Cookie, HSTS, CSP 등 보안 헤더 확인
6. EventBridge + SNS 기반 보안 이벤트 탐지·알림 구조 설명

## 전자금융 관련 규정 대응 관점

| 규정 요구 영역 | 프로젝트 대응 |
| --- | --- |
| 접근통제 | VPC 계층 분리, Private Subnet, Security Group 최소 접근, ALB 직접 접근 제한 검토 |
| 암호화 | RDS 저장 데이터 암호화, KMS, HTTPS, App -> RDS TLS, CloudFront Viewer mTLS PoC |
| 인증 | Cognito MFA, CloudFront Viewer mTLS 기반 클라이언트 인증 PoC |
| 로그 및 감사 | CloudTrail, CloudWatch Logs, VPC Flow Logs, CloudFront Standard/Connection Logs |
| 이상 이벤트 대응 | EventBridge Rule, SNS 알림, Runbook 기반 확인 및 조치 |
| 백업 및 보관 | AWS Backup, S3 로그 보관, Lifecycle/Object Lock 선택 구성 |

## 향후 개선 과제

- ALB -> App 구간 HTTPS 또는 mTLS 운영 적용 검토
- CloudFront WAF 별도 적용 및 `us-east-1` WebACL 운영 정책 수립
- WAF Rate Rule의 `count` -> `block` 전환 기준 수립
- VPC Endpoint Policy를 리소스 ARN과 Action 기준으로 세분화
- ACM 인증서 발급·갱신 자동화와 만료 알림 고도화
- KMS Key Rotation 운영 자동화
- Security Hub, GuardDuty, AWS Config 활성화 후 Findings 통합 관제 확장
- SIEM 대시보드 연동 및 인시던트 리포트 자동화

## 주의 사항

- `terraform.tfvars`에는 계정 정보, 인증서 ARN, 이메일, 도메인 등 환경별 값이 포함될 수 있으므로 커밋하지 않습니다.
- GuardDuty, Security Hub, AWS Config는 기본값이 비활성화되어 있습니다. 발표와 문서에서는 실제 활성화 증적이 있는 항목과 향후 과제를 분리해야 합니다.
- `End-to-End 암호화` 표현은 ALB -> App 구간까지 HTTPS/mTLS가 적용된 경우에만 사용합니다. 현재 기본 구성에서는 주요 외부 전송 구간 암호화 강화로 표현합니다.
- CloudFront Viewer mTLS는 CloudFront, Trust Store, 인증서, 로그 설정이 모두 맞아야 검증 가능합니다.

## 라이선스 및 사용 범위

이 저장소는 교육용 보안 아키텍처 실습과 프로젝트 발표를 위한 예제입니다. 실제 운영 환경에 적용할 때는 조직의 보안 정책, 비용 정책, 개인정보 처리 기준, 인증서 관리 기준, 규제 요구사항을 별도로 검토해야 합니다.
