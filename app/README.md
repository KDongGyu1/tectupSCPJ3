# FinPay Python 앱 프로토타입

이 폴더는 FinPay 실제 애플리케이션 개발을 위한 Python 기반 로컬 프로토타입이다.

현재 버전은 화면 흐름과 역할 기반 접근 제어를 먼저 구현한 단계이며, 이후 Cognito, RDS, Secrets Manager, CloudWatch와 연결한다.

## 실행 방법

```powershell
cd C:\project\tectupSCPJ3
python app\server.py
```

접속 주소:

```text
http://127.0.0.1:8088
```

## 데모 계정

| 계정 | 역할 | 사용 기능 |
|---|---|---|
| `customer@finpay.local` | Customer | 결제 요청 생성 |
| `merchant@finpay.local` | Merchant | 결제 요청 생성, 결제 내역 확인 |
| `settlement@finpay.local` | SettlementOperator | 결제 승인/거절 |
| `auditor@finpay.local` | Auditor | 감사 이벤트 조회 |
| `ops@finpay.local` | OperationsAdmin | 결제 승인, 시스템 상태 확인 |
| `security@finpay.local` | SecurityAdmin | 보안 상태, 감사 이벤트 확인 |

현재 로그인은 실제 Cognito가 아니라 데모 계정 선택 방식이다. Cognito Hosted UI와 JWT 검증은 다음 구현 단계에서 연결한다.

## AWS 연동 환경변수

Terraform output 값을 앱 실행 환경변수로 주입하면 시스템 상태 화면과 API에서 연동 준비 상태를 확인할 수 있다.

```powershell
$env:FINPAY_ENV="dev"
$env:FINPAY_STORAGE="postgres"
$env:AWS_REGION="ap-northeast-2"
$env:COGNITO_USER_POOL_ID="<terraform output cognito_user_pool_id>"
$env:COGNITO_WEB_CLIENT_ID="<terraform output cognito_web_client_id>"
$env:RDS_ENDPOINT="<terraform output rds_endpoint>"
$env:RDS_MASTER_SECRET_ARN="<terraform output rds_master_secret_arn>"
$env:CLOUDWATCH_LOG_GROUP="/finpay/finpay-dev/payment"
python app\server.py
```

PostgreSQL 저장소를 사용하려면 의존성을 먼저 설치한다.

```powershell
python -m pip install -r app\requirements.txt
```

DB 접속 정보는 두 방식 중 하나로 제공한다.

```powershell
$env:DATABASE_URL="postgresql://finpay_admin:<password>@<rds-endpoint>:5432/finpay"
```

또는:

```powershell
$env:RDS_ENDPOINT="<terraform output rds_endpoint>"
$env:DB_NAME="finpay"
$env:DB_USER="finpay_admin"
$env:DB_PASSWORD="<password>"
```

`RDS_MASTER_SECRET_ARN`과 `boto3`가 설정되어 있으면 Secrets Manager에서 RDS 관리 비밀값을 조회해 접속 정보를 사용할 수 있다.

## 화면 구성

| 화면 | 경로 | 목적 |
|---|---|---|
| 로그인 | `/login` | 사용자 역할 선택 |
| 대시보드 | `/dashboard` | 결제, 승인, 감사 이벤트 현황 확인 |
| 내 권한 | `/my-access` | 현재 사용자 역할과 접근 가능 메뉴 확인 |
| 결제 생성 | `/payments/new` | Customer/Merchant 결제 요청 생성 |
| 결제 승인 | `/payments/review` | SettlementOperator/Ops 결제 승인 또는 거절 |
| 결제 내역 | `/payments` | 결제 상태 변경 결과 확인 |
| 결제 상세 | `/detail?id={payment_id}` | 결제 상세 정보와 처리 이력 확인 |
| 감사 이벤트 | `/audit/events` | 로그인, 결제, 차단 이벤트 기록 확인 |
| 보안 상태 | `/security/status` | 보안 운영 상태와 차단 이벤트 기록 |
| 시스템 상태 | `/system/status` | 앱 런타임과 API 상태 확인 |
| 접근 거부 | 자동 403 | 권한 없는 접근 차단 |

## 현재 구현된 주요 기능

- 역할별 메뉴 표시
- 사용자 역할/허용 메뉴 확인
- 역할별 결제 데이터 조회 범위 분리
- Local JSON / PostgreSQL 저장소 전환
- 결제 요청 생성
- 결제 승인/거절
- 결제 상세 조회
- 결제 상태/검색어 필터
- 결제 상태 분포 요약
- 감사 이벤트 기록
- 감사 이벤트 결과/검색어 필터
- 감사 이벤트 요약 지표
- 결제 처리 후 성공/거절 알림 메시지
- 결제 상세 처리 이력
- 결제/감사 이벤트 CSV 내보내기
- 권한 없는 접근 차단 화면

## API

```text
GET http://127.0.0.1:8088/api/health
GET http://127.0.0.1:8088/api/db-check
GET http://127.0.0.1:8088/api/config
GET http://127.0.0.1:8088/api/me
GET http://127.0.0.1:8088/api/payments
GET http://127.0.0.1:8088/api/audit-events
GET http://127.0.0.1:8088/export/payments.csv
GET http://127.0.0.1:8088/export/audit-events.csv
```

## 로컬 데이터

앱 실행 중 생성되는 개발용 데이터는 아래 경로에 저장된다.

```text
app\data\finpay-data.json
```

이 데이터는 로컬 실행 산출물이므로 Git에는 포함하지 않는다.

PostgreSQL 모드에서는 앱이 시작 시 필요한 테이블을 자동 생성한다. 동일한 DDL은 `app\schema.sql`에도 정리되어 있다.

## 다음 구현 단계

- Cognito Hosted UI 로그인 연결
- RDS PostgreSQL 저장소 연결
- Secrets Manager 기반 DB 접속 정보 로딩
- CloudWatch 구조화 로그 기록
- 감사 이벤트 시각화 화면 보강
