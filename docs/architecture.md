# 아키텍처 개요

현재 Terraform 실행 진입점은 저장소 루트 디렉터리이다.

## 구성 계층

- 네트워크: VPC, 퍼블릭 서브넷, 프라이빗 애플리케이션 서브넷, 격리된 데이터베이스 서브넷, 게이트웨이, 라우팅 테이블, VPC 엔드포인트로 구성한다.
- 엣지: 외부 트래픽 진입점인 Public ALB에 WAF를 연결한다.
- 애플리케이션: 애플리케이션 서비스는 프라이빗 EC2 Auto Scaling Group으로 배치한다.
- 인증: Cognito User Pool과 App Client로 애플리케이션 인증 기반을 구성한다.
- 데이터: RDS PostgreSQL을 격리된 데이터베이스 서브넷에 배치한다.
- 보안 및 운영: KMS, IAM Role, CloudTrail, VPC Flow Logs, CloudWatch Logs, 중앙 S3 로그 저장소, AWS Backup, 선택형 컴플라이언스 서비스를 포함한다.

## 활성 코드 기준

`modules/` 하위의 모듈형 Terraform 구성이 현재 인프라 코드의 기준이다.
