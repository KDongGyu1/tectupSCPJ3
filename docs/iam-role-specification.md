# IAM Role Specification

현재 IAM 구현은 `modules/iam`에 정의되어 있다.

## Roles

- Operations administrator role: MFA 기반 접근을 전제로 인프라 운영 작업을 수행하기 위한 역할이다.
- Security administrator role: 보안 설정 관리와 모니터링 작업을 수행하기 위한 역할이다.
- Auditor role: 읽기 전용 감사 및 검토 업무를 수행하기 위한 역할이다.
- Application instance profile: private EC2 application instances에 연결되는 실행 역할이다.

## Notes

IAM Identity Center assignments는 일반적으로 AWS Organizations 또는 account administration layer에서 운영한다. 이 Terraform 프로젝트는 workload에 필요한 IAM roles와 policies 구성을 중심으로 다룬다.
