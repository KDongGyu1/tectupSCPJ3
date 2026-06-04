# 전송보안 개선 과제 목록

기준: Terraform 코드에서 확인된 통신 경로와 AWS CLI 조회 결과를 기준으로 우선순위를 부여했다. 비용 또는 운영 복잡도가 있는 CloudFront, Route 53, ACM, AWS Config 관련 항목은 심화 개선 과제로 분류했다.

| 우선순위 | 개선 과제 | 현재 상태 | 개선 방향 | 실제 구현 가능 여부 | Terraform 수정 필요 파일 | 검증 방법 |
|---|---|---|---|---|---|---|
| P1 | CloudFront -> ALB HTTPS 적용 | 코드: CloudFront OriginProtocolPolicy가 `http-only`. CLI: 실제 배포도 `http-only` 확인. | ALB에 ACM 인증서 적용 후 CloudFront OriginProtocolPolicy를 `https-only`로 변경. | 가능. ACM 인증서와 도메인 검증 필요. | `modules/app/main.tf`, `variables.tf`, `terraform.tfvars.example` | `aws cloudfront get-distribution-config --id E2V5455X4MM78W`에서 `OriginProtocolPolicy=https-only` 확인 |
| P1 | 사용자 HTTP -> HTTPS 리다이렉트 | 코드: CloudFront ViewerProtocolPolicy는 `redirect-to-https`. ALB HTTP 80 Listener는 Target Group forward. | CloudFront는 현 상태 유지. ALB 80은 HTTPS Listener 준비 후 redirect로 변경. | 가능. ALB 인증서 필요. | `modules/app/main.tf`, `variables.tf` | `curl -I http://ALB_DNS`가 301/302 HTTPS redirect 또는 접근 차단되는지 확인 |
| P2 | ALB -> App HTTPS 적용 검토 | 코드: Target Group protocol `HTTP`, port 8080. | App에 TLS 종단을 추가하거나 Nginx/Envoy sidecar, ACM Private CA, 서비스 메시 방식 검토. | 가능하지만 운영 복잡도 있음. 심화 개선 과제. | `modules/app/main.tf`, `modules/app/user_data.sh.tftpl`, `app/server.py` | `aws elbv2 describe-target-groups`에서 protocol HTTPS 확인, health check 정상 확인 |
| P1 | App -> RDS TLS 적용 | 코드: 앱 DB 연결 문자열에 `sslmode` 없음. RDS 저장 데이터 암호화와는 별개로 전송 TLS 강제는 코드상 확인되지 않음. | `sslmode=require`를 우선 적용하고, 가능하면 RDS CA 번들 기반 `verify-full` 적용. | 가능. 앱 코드 수정 필요. | `app/server.py`, `modules/app/user_data.sh.tftpl` | `rg -n "sslmode" app/server.py`, 앱 `/system/status`, RDS 세션 SSL 여부 확인 |
| P2 | WAF Count -> Block 전환 기준 | 코드: RateLimitAuth/Payments/Transactions/Ops/Audit가 `count {}`. | 관찰 기간 동안 false positive 확인 후 `/auth`, `/payments`, `/ops` 등 경로별 Block 기준 수립. | 가능. 운영 관찰 필요. | `modules/waf/main.tf` | WAF sampled requests와 CloudWatch metric 확인 후 rule action이 Block인지 확인 |
| P2 | SQLi Rule / Rate Rule 강화 | 코드: AWSManagedRulesSQLiRuleSet 존재. Rate Rule은 경로별 Count 모드. | 결제/인증 경로 rate limit을 실제 트래픽 기준으로 조정하고 SQLi 탐지 결과를 점검. | 가능. | `modules/waf/main.tf` | `aws wafv2 get-web-acl-for-resource --region ap-northeast-2 --resource-arn $ALB_ARN` |
| P1 | ALB 직접 접근 제한 | 코드: ALB SG가 기본적으로 `0.0.0.0/0`에서 80/443 허용. CLI: ALB DNS 직접 HTTP 응답 확인. | ALB SG를 CloudFront origin-facing prefix list로 제한. 추가로 CloudFront custom header와 WAF 조건 적용 검토. | 가능. CloudFront 대역 관리 방식 결정 필요. | `modules/security_groups/main.tf`, `variables.tf`, `modules/app/main.tf`, `modules/waf/main.tf` | `curl -I http://ALB_DNS` 직접 접근 차단 확인, CloudFront URL 정상 확인 |
| P2 | VPC Endpoint Policy 강화 | 코드: S3 Gateway Endpoint와 Interface Endpoint에 별도 policy 없음. CLI: 기본 Allow 정책 확인. | S3 artifact bucket, Secrets Manager secret, KMS key, Logs 권한을 필요한 ARN/Action으로 제한. | 가능. 정책 설계 필요. | `modules/network/main.tf`, `modules/vpc_endpoints/main.tf`, `modules/iam/main.tf` | `aws ec2 describe-vpc-endpoints --region ap-northeast-2 --filters Name=vpc-id,Values=$VPC_ID`에서 PolicyDocument 확인 |
| P3 | mTLS 후보 구간 선정 | 코드: mTLS 관련 설정 없음. ALB Target Group은 HTTP. | 후보 1: ALB -> App. 후보 2: App 내부 서비스 간. 후보 3: 관리자/운영자 접근 경로 `/ops/*`. | 설계상 가능. 실제 구현은 심화 개선 과제. | `modules/app/main.tf`, `modules/security_groups/main.tf`, `app/server.py` | 설계 문서화 후 PoC. ALB mutual authentication 또는 Private CA/sidecar 방식 비교 |
| P1 | 보안그룹 변경 탐지 알림 검증 | 코드: EventBridge Rule이 SG 변경 API를 SNS로 전달. CLI: Rule enabled, SNS target, email subscription 확인. | 테스트용 SG rule 추가/삭제 후 SNS 이메일 수신 여부 확인. `alert_email` 변수와 구독 Confirm 상태 관리. | 가능. 실제 운영 테스트 필요. | `modules/automation/main.tf`, `variables.tf`, `terraform.tfvars.example` | `aws events describe-rule`, `aws events list-targets-by-rule`, `aws sns list-subscriptions`, 테스트 변경 이벤트 수신 확인 |
| P2 | CloudFront WAF 적용 검토 | 코드: WAF는 Regional scope로 ALB에 연결. CloudFront WebACL 없음. | CloudFront용 WAF는 `us-east-1` CLOUDFRONT scope로 별도 생성 후 Distribution에 연결. | 가능. 비용/운영 정책 고려 필요. 심화 개선 과제. | 신규 또는 확장: `modules/waf/main.tf`, `modules/app/main.tf`, `versions.tf` provider alias 검토 | `aws wafv2 list-web-acls --region us-east-1 --scope CLOUDFRONT`, `aws cloudfront get-distribution-config` |
| P3 | Route 53 / ACM 기반 운영 도메인 HTTPS | 코드: Route 53 리소스 없음. ALB 인증서 ARN 변수 기본값 빈 값. CloudFront는 기본 인증서 사용. | 운영 도메인 확보, ACM 인증서 발급, CloudFront alias와 Route 53 record 구성. | 가능. 도메인/비용/검증 필요. 심화 개선 과제. | 신규 모듈 또는 `modules/app/main.tf`, `variables.tf`, `terraform.tfvars.example` | `aws acm list-certificates`, `aws route53 list-hosted-zones`, 브라우저 인증서 확인 |

## 요약 판단

- 전송보안의 최우선 과제는 CloudFront -> ALB HTTPS, ALB 직접 접근 제한, App -> RDS TLS 적용이다.
- 사용자 -> CloudFront HTTPS 리다이렉트는 구현되어 있으나 ALB 직접 HTTP 접근은 남아 있다.
- ALB -> App HTTPS와 mTLS는 구현보다 설계 검토가 먼저 필요한 심화 과제다.
- WAF Rate Rule은 현재 Count 모드이므로 운영 관찰 후 Block 전환 기준을 별도로 확정해야 한다.
