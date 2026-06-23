# FinPay Python 앱

FinPay 실제 애플리케이션 개발 및 6단계 테스트를 위한 Python 기반 앱입니다. 최종 앱은 CloudFront, ALB, Auto Scaling, Cognito, RDS, Secrets Manager, CloudWatch와 연동됩니다.

## 기준 역할

프로젝트 역할은 아래 5개만 사용합니다.

| 계정 | 역할 | 주요 기능 |
|---|---|---|
| `customer@finpay.local` | Customer | 결제 요청 생성, 본인 결제 조회 |
| `merchant@finpay.local` | Merchant | 가맹점 결제 요청 생성, 관련 결제 조회 |
| `settlement@finpay.local` | SettlementOperator | 결제 승인 또는 거절 |
| `auditor@finpay.local` | Auditor | 결제 내역과 감사 이벤트 조회 |
| `ops@finpay.local` | OperationsAdmin | 운영, 승인, 감사, 시스템 상태 확인 |
`r`n
## 로컬 실행

```powershell
cd C:\project\tectupSCPJ3
python app\server.py
```

기본 접속 주소는 아래와 같습니다.

```text
http://127.0.0.1:8088
```

## AWS 실행 환경변수

```powershell
$env:FINPAY_ENV="dev"
$env:FINPAY_STORAGE="postgres"
$env:AWS_REGION="ap-northeast-2"
$env:APP_BASE_URL="<terraform output -raw app_base_url>"
$env:COGNITO_HOSTED_UI_URL="https://finpay-dev-581586866411.auth.ap-northeast-2.amazoncognito.com"
$env:COGNITO_USER_POOL_ID="<terraform output -raw cognito_user_pool_id>"
$env:COGNITO_WEB_CLIENT_ID="<terraform output -raw cognito_web_client_id>"
$env:RDS_ENDPOINT="<terraform output -raw rds_endpoint>"
$env:DB_NAME="finpay"
$env:RDS_MASTER_SECRET_ARN="<terraform output -raw rds_master_secret_arn>"
$env:CLOUDWATCH_LOG_GROUP="/finpay/finpay-dev/payment"
$env:CLOUDWATCH_LOG_STREAM="finpay-real-alb"
python app\server.py
```

## 주요 화면

| 화면 | 경로 | 목적 |
|---|---|---|
| 로그인 | `/login` | Cognito Hosted UI 로그인 시작 |
| 대시보드 | `/dashboard` | 결제, 승인, 감사 이벤트 요약 |
| 내 권한 | `/my-access` | 현재 역할과 허용 메뉴 확인 |
| 결제 생성 | `/payments/new` | Customer/Merchant 결제 요청 생성 |
| 결제 승인 | `/payments/review` | SettlementOperator/Ops 결제 승인 또는 거절 |
| 결제 내역 | `/payments` | 결제 상태와 상세 조회 |
| 감사 이벤트 | `/audit/events` | Auditor/Ops 감사 이벤트 조회 |
| 보안 상태 | `/security/status` | OperationsAdmin 보안 상태와 차단 이벤트 기록 |
| 시스템 상태 | `/system/status` | OperationsAdmin AWS 연동 상태 확인 |

## API

```http
GET /health
GET /api/health
GET /api/db-check
GET /api/config
GET /api/me
GET /api/payments
GET /api/audit-events
GET /export/payments.csv
GET /export/audit-events.csv
```

## 배포 확인

```powershell
curl http://finpay-dev-alb-1447356258.ap-northeast-2.elb.amazonaws.com/health
aws autoscaling describe-instance-refreshes `
  --auto-scaling-group-name finpay-dev-payment-asg `
  --region ap-northeast-2 `
  --profile jungwoo `
  --query "InstanceRefreshes[0].{Status:Status,Percent:PercentageComplete,Reason:StatusReason}" `
  --output table
```
