# 보안 정책 매트릭스

| 영역 | 활성 모듈 | 목적 |
| --- | --- | --- |
| 네트워크 격리 | `network`, `security_groups` | 퍼블릭, 애플리케이션, 데이터베이스 계층을 분리한다. |
| 네트워크 컴플라이언스 검토 | `security_groups`, `waf`, `vpc_endpoints` | 외부 접근통제 위반 기준, 점검 명령어, 대응 절차를 정의한다. |
| 네트워크 변경 탐지 | `automation`, `logging` | CloudTrail EC2 API 이벤트에서 Security Group 변경을 탐지하고 SNS로 알림을 전송한다. |
| 프라이빗 AWS 접근 | `vpc_endpoints` | 지원되는 AWS 서비스에 대해 퍼블릭 인터넷 의존도를 줄인다. |
| 암호화 | `kms`, `data`, `logging` | 데이터베이스, 로그, 관련 인프라 데이터를 암호화한다. |
| 엣지 보호 | `waf` | ALB 트래픽에 AWS 관리형 규칙과 경로별 Rate Limit을 적용한다. |
| 자격 증명 및 인증 | `iam`, `auth` | 워크로드 역할과 Cognito 기반 애플리케이션 인증을 제공한다. |
| 로깅 | `logging` | CloudTrail, VPC Flow Logs, 활성화 시 ALB 로그, CloudWatch Logs를 중앙화한다. |
| 컴플라이언스 모니터링 | `compliance` | GuardDuty, Security Hub, AWS Config를 선택적으로 활성화한다. |
| 복구 | `backup` | RDS 백업 적용 범위를 관리한다. |
| 감사 자동화 | `automation` | 감사 보고서 생성과 SNS 알림을 예약 실행한다. |

예상치 못한 비용이나 계정 구독 오류를 방지하기 위해 선택형 통제 항목은 `terraform.tfvars.example`에서 기본 비활성화되어 있다.
