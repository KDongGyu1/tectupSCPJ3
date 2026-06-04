# 공격면 분석표

기준: Terraform 코드에서 확인된 방어 수단과 AWS CLI로 확인한 실제 배포 상태를 구분했다. 코드상 확인되지 않는 항목은 추측하지 않고 별도 확인 필요로 표시했다.

| 공격면 | 발생 가능한 위험 | 현재 방어 수단 | 현재 판단 | 위험도 | 개선 방안 | 추가 확인 명령어 |
|---|---|---|---|---|---|---|
| DB Public Access | RDS가 인터넷에 직접 노출되어 데이터 유출, 무차별 대입, 취약점 공격 대상이 될 수 있음. | 코드: `publicly_accessible = false`, DB Subnet Group 사용, DB SG는 App SG만 허용. CLI: `PubliclyAccessible=false` 확인. | 정상 | 낮음 | 현재 구성 유지. 운영 단계에서는 deletion protection, final snapshot도 함께 강화. | `aws rds describe-db-instances --region ap-northeast-2` |
| SSH 22번 오픈 | EC2 직접 로그인 공격, 키 탈취, 스캔 대상 증가. | 코드: ALB/App/DB/VPCE SG에 TCP 22 inbound 없음. App 인스턴스는 SSM IAM Role 사용. | 정상 | 낮음 | SSH 대신 SSM Session Manager 유지. | `aws ec2 describe-security-groups --region ap-northeast-2` |
| DB 포트 외부 오픈 | PostgreSQL 5432가 외부에 노출되어 직접 공격 가능. | 코드: DB SG inbound 5432 source는 App SG만 허용. | 정상 | 낮음 | 현재 구성 유지. | `aws ec2 describe-security-groups --region ap-northeast-2 --filters Name=group-name,Values=finpay-dev-db-sg` |
| App 서버 직접 접근 | ALB/WAF를 우회해 App 포트 8080으로 직접 공격 가능. | 코드: App SG inbound 8080 source는 ALB SG만 허용. App Subnet Public IP auto-assign false. CLI: App EC2 Public IP 없음 확인. | 정상 | 낮음 | 현재 구성 유지. ASG 신규 인스턴스 Public IP 여부도 주기 점검. | `aws ec2 describe-instances --region ap-northeast-2 --filters Name=vpc-id,Values=$VPC_ID` |
| ALB 직접 접근 | CloudFront를 우회하여 ALB DNS로 직접 요청 가능. Origin 보호, 캐싱 정책, CloudFront 보안 정책을 우회할 수 있음. | 코드: ALB에는 WAF 연결. 단, ALB SG 기본 허용 CIDR은 `0.0.0.0/0`. CLI: ALB 직접 HTTP 응답 확인. | 개선 필요 | 중간~높음 | ALB SG를 CloudFront origin-facing prefix list로 제한. 추가로 CloudFront custom header + WAF 조건 검토. | `curl -I http://finpay-dev-alb-2007566830.ap-northeast-2.elb.amazonaws.com` |
| WAF 미연결 또는 Rule 부족 | SQLi, 악성 IP, 비정상 요청, 과도한 요청이 애플리케이션까지 도달 가능. | 코드: ALB용 Regional WebACL, AWS Managed Rules, SQLi Rule, path 기반 Rate Rule 구성. CLI: ALB association 확인. | 연결은 정상, Rate Rule은 Count | 중간 | Rate Rule 관찰 기간 후 Block 전환 기준 수립. CloudFront WebACL 적용 검토. | `aws wafv2 get-web-acl-for-resource --region ap-northeast-2 --resource-arn $ALB_ARN` |
| CloudFront 미사용 또는 HTTPS 미강제 | 사용자 구간 평문 통신, CDN/WAF 우회, TLS 정책 약화. | 코드: CloudFront Distribution 있음. ViewerProtocolPolicy는 `redirect-to-https`. CLI: CloudFront 배포 존재 확인. | 사용자 -> CloudFront는 부분 정상 | 중간 | CloudFront에 WebACL 연결 검토. 실제 Minimum TLS 정책 재확인. Route 53/ACM은 심화 개선 과제. | `aws cloudfront get-distribution-config --id E2V5455X4MM78W` |
| CloudFront -> ALB HTTP 구간 | Edge 이후 Origin 구간이 평문 HTTP로 전달되어 전송보안 요구사항에 미흡. | 코드: OriginProtocolPolicy `http-only`. | 개선 필요 | 중간 | ALB ACM 인증서 적용 후 OriginProtocolPolicy를 `https-only`로 변경. | `aws cloudfront get-distribution-config --id E2V5455X4MM78W` |
| 사용자 -> ALB HTTP 직접 접근 | CloudFront를 거치지 않고 ALB HTTP 80으로 직접 요청 가능. | 코드: ALB HTTP 80 Listener는 forward 동작. HTTPS Listener는 인증서 ARN이 있을 때만 생성. | 개선 필요 | 중간 | ALB HTTP를 HTTPS redirect로 변경하고 ALB 직접 접근 제한 적용. | `aws elbv2 describe-listeners --region ap-northeast-2 --load-balancer-arn $ALB_ARN` |
| ALB -> App HTTP 구간 | 내부 App 구간 트래픽이 HTTP 8080으로 전달되어 내부 구간 암호화가 미흡. | 코드: Target Group protocol `HTTP`, port 8080. | HTTP로 추정 | 중간 | App TLS, Nginx/Envoy sidecar, ACM Private CA 또는 서비스 메시 검토. | `aws elbv2 describe-target-groups --region ap-northeast-2 --load-balancer-arn $ALB_ARN` |
| App -> RDS TLS 미확인 | DB 인증정보와 쿼리가 TLS 없이 전송될 가능성. | 코드: RDS 저장 데이터 암호화는 있음. 앱 `postgres_conninfo()`에 `sslmode` 없음. | 추가 확인 필요 | 중간 | `sslmode=require` 우선 적용, 가능하면 `verify-full`과 CA 검증 적용. | `rg -n "sslmode|postgres_conninfo|psycopg" app/server.py` |
| VPC Endpoint 미사용 | Private App 리소스가 AWS API 접근 시 NAT/인터넷 의존도가 증가. | 코드: S3 Gateway Endpoint, KMS/Secrets Manager/Logs/SSM 계열 Interface Endpoint 구성. CLI: available 확인. | 핵심 Endpoint 사용 중 | 낮음~중간 | 필요한 AWS 서비스 누락 여부 점검. Endpoint Policy 최소 권한화. | `aws ec2 describe-vpc-endpoints --region ap-northeast-2 --filters Name=vpc-id,Values=$VPC_ID` |
| VPC Endpoint Policy 과다 허용 | Endpoint를 통한 AWS API 접근 범위가 필요 이상으로 넓어질 수 있음. | 코드: 별도 policy 설정 없음. CLI: 기본 Allow 정책 확인. | 개선 필요 | 중간 | S3, Secrets Manager, KMS, Logs Endpoint Policy를 필요한 ARN/Action으로 제한. | `aws ec2 describe-vpc-endpoints --region ap-northeast-2 --filters Name=vpc-id,Values=$VPC_ID` |
| 과도한 Security Group egress | App 서버가 의도치 않은 외부 HTTPS 목적지로 통신 가능. | 코드: App SG egress 443 to `0.0.0.0/0`, DB egress 없음, ALB egress 8080 to VPC CIDR. | App egress 개선 후보 | 중간 | Endpoint 사용 서비스는 Endpoint/Prefix 기반으로 축소. 외부 결제 API 등 필요한 목적지만 정책화. | `aws ec2 describe-security-groups --region ap-northeast-2 --filters Name=group-name,Values=finpay-dev-app-sg` |
| 보안그룹 변경 알림 미수신 가능성 | SG 변경이 발생해도 알림 수신자가 없거나 구독 미확인 상태일 수 있음. | 코드: EventBridge Rule, SNS Topic, 이메일 구독 조건부 생성. CLI: 실제 Rule enabled, target SNS, email subscription 존재 확인. | 대체로 정상, 수신 테스트 필요 | 낮음~중간 | `alert_email` 배포 변수 관리. SNS Confirm 상태와 실제 수신 테스트 수행. | `aws events describe-rule --region ap-northeast-2 --name finpay-dev-security-group-changes && aws sns list-subscriptions --region ap-northeast-2` |
| AWS Config 미활성화 | 설정 변경에 대한 지속적 컴플라이언스 평가가 제한됨. | 코드: AWS Config 모듈은 있으나 `enable_aws_config` 기본값 false. | 심화 개선 과제 | 중간 | 비용/계정 제약 확인 후 핵심 Managed Rule 활성화 검토. | `aws configservice describe-configuration-recorders --region ap-northeast-2` |

## 요약 판단

- DB, SSH, App 직접 접근 공격면은 현재 코드 기준으로 잘 통제되어 있다.
- 가장 중요한 외부 공격면은 ALB 직접 접근과 HTTP 기반 Origin/App 구간이다.
- VPC Endpoint는 구성되어 있으나 Endpoint Policy와 App egress는 최소 권한 관점에서 개선 여지가 있다.
- 보안그룹 변경 탐지는 구현되어 있으나 실제 알림 수신 테스트가 필요하다.
