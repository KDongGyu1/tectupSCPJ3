# Architecture Overview

현재 Terraform 실행 진입점은 저장소 루트 디렉터리이다.

## Layers

- Network: VPC, public subnets, private app subnets, isolated database subnets, gateways, route tables, VPC endpoints로 구성한다.
- Edge: 외부 트래픽 진입점인 Public ALB에 WAF를 연결한다.
- Application: 애플리케이션 서비스는 private EC2 Auto Scaling Group으로 배치한다.
- Authentication: Cognito User Pool과 App Client로 애플리케이션 인증 기반을 구성한다.
- Data: RDS PostgreSQL을 isolated database subnets에 배치한다.
- Security and operations: KMS, IAM roles, CloudTrail, VPC Flow Logs, CloudWatch Logs, central S3 log storage, AWS Backup, optional compliance services를 포함한다.

## Active Code

`modules/` 하위의 modular Terraform structure가 현재 인프라 코드의 기준이다.
