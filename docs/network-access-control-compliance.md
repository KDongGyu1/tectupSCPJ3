# 네트워크 접근통제 컴플라이언스

이 문서는 FinPay Terraform 아키텍처의 네트워크 접근통제 검토 기준을 정의한다.

## 적용 범위

| 영역 | Terraform 리소스 | 검토 목적 |
| --- | --- | --- |
| Security Group | `modules/security_groups` | ALB, App, DB, VPC Endpoint 간 계층 기반 접근통제가 적용되어 있는지 확인한다. |
| WAF | `modules/waf` | Public ALB 트래픽이 관리형 규칙과 Rate Limit 모니터링으로 보호되는지 확인한다. |
| 변경 탐지 | `modules/automation` | CloudTrail 이벤트와 EventBridge 알림을 통해 Security Group 변경을 탐지한다. |
| VPC Endpoint | `modules/network`, `modules/vpc_endpoints` | AWS 서비스 접근 경로가 프라이빗하게 구성되어 있고 퍼블릭 인터넷 의존도가 줄어드는지 확인한다. |
| 서브넷 및 라우팅 | `modules/network` | 퍼블릭 서브넷, 프라이빗 App 서브넷, 격리 DB 서브넷의 동작을 확인한다. |

## 네트워크 위반 기준

| No. | 점검 항목 | 정상 기준 | 위반 기준 | 심각도 | 증빙 |
| --- | --- | --- | --- | --- | --- |
| 1 | DB Security Group 노출 | DB SG는 App SG에서 오는 PostgreSQL `5432`만 허용한다. | DB SG가 `0.0.0.0/0`, `::/0`, 퍼블릭 CIDR 또는 ALB SG 직접 접근을 허용한다. | 위험 | `aws ec2 describe-security-groups` |
| 2 | App Security Group 출발지 | App SG는 ALB SG에서 오는 서비스 포트 `8080`만 허용한다. | App SG가 `0.0.0.0/0`, `::/0`, 사무실 CIDR, SSH 또는 사용자 직접 접근을 허용한다. | 위험 | `aws ec2 describe-security-groups` |
| 3 | SSH 노출 | ALB, App, DB, VPCE SG에 인바운드 `22` 규칙이 없어야 한다. | TCP `22`가 임의 CIDR 또는 승인되지 않은 출발지에 열려 있다. | 위험 | `aws ec2 describe-security-groups` |
| 4 | Public IP 할당 | App 및 DB 서브넷은 `map_public_ip_on_launch = false`이고, App EC2 인스턴스는 Public IP가 없어야 한다. | App/DB 서브넷이 Public IP를 자동 할당하거나 프라이빗 EC2에 Public IP가 있다. | 위험 | `aws ec2 describe-subnets`, `aws ec2 describe-instances` |
| 5 | DB 서브넷 라우팅 | DB 라우팅 테이블에는 IGW 또는 NAT로 향하는 `0.0.0.0/0` 라우트가 없어야 한다. | DB 서브넷에 퍼블릭 또는 기본 인터넷 라우트가 있다. | 위험 | `aws ec2 describe-route-tables` |
| 6 | ALB 퍼블릭 노출 | 외부 HTTP/HTTPS 접근 허용은 서비스 정책에 따라 ALB SG에만 허용한다. | App 또는 DB 계층이 ALB를 거치지 않고 외부에서 직접 접근 가능하다. | 위험 | SG, 라우팅 테이블, EC2 Public IP 점검 |
| 7 | WAF 연결 | WAF Web ACL이 Public ALB에 연결되어 있어야 한다. | ALB에 WAF가 연결되어 있지 않다. | 위험 | `aws wafv2 get-web-acl-for-resource` |
| 8 | VPC Endpoint 접근 | Interface Endpoint SG는 App SG에서 오는 `443`만 허용한다. | Endpoint SG가 `0.0.0.0/0` 또는 관련 없는 SG에서 오는 `443`을 허용한다. | 주의/위험 | `aws ec2 describe-vpc-endpoints`, SG 점검 |
| 9 | ALB Listener 정책 | HTTP `80`은 서비스 정책상 허용될 때만 사용하고, ACM 설정 시 HTTPS `443`을 우선한다. | Public Listener가 불필요한 포트 또는 검토되지 않은 프로토콜을 노출한다. | 주의 | `aws elbv2 describe-listeners` |

## 네트워크 점검 명령어 세트

먼저 공통 변수를 설정한다.

```bash
export AWS_PROFILE=fintech
export AWS_REGION=ap-northeast-2
export NAME_PREFIX=finpay-dev

aws sts get-caller-identity
```

Security Group 규칙을 확인한다.

```bash
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${NAME_PREFIX}-alb-sg,${NAME_PREFIX}-app-sg,${NAME_PREFIX}-db-sg,${NAME_PREFIX}-vpce-sg" \
  --query 'SecurityGroups[*].{GroupName:GroupName,GroupId:GroupId,Ingress:IpPermissions,Egress:IpPermissionsEgress}' \
  --output json
```

SSH가 퍼블릭으로 열려 있는지 확인한다.

```bash
aws ec2 describe-security-groups \
  --query 'SecurityGroups[?IpPermissions[?FromPort==`22` && ToPort==`22`]].{GroupName:GroupName,GroupId:GroupId,Ingress:IpPermissions}' \
  --output table
```

서브넷 Public IP 자동 할당 설정을 확인한다.

```bash
aws ec2 describe-subnets \
  --filters "Name=tag:Project,Values=finpay" \
  --query 'Subnets[*].{Name:Tags[?Key==`Name`]|[0].Value,SubnetId:SubnetId,AZ:AvailabilityZone,MapPublicIpOnLaunch:MapPublicIpOnLaunch,Cidr:CidrBlock}' \
  --output table
```

실행 중인 EC2의 Public IP 할당 여부를 확인한다.

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=finpay" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`]|[0].Value,InstanceId:InstanceId,SubnetId:SubnetId,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress,State:State.Name}' \
  --output table
```

라우팅 테이블을 확인한다.

```bash
aws ec2 describe-route-tables \
  --filters "Name=tag:Project,Values=finpay" \
  --query 'RouteTables[*].{Name:Tags[?Key==`Name`]|[0].Value,RouteTableId:RouteTableId,Routes:Routes,Associations:Associations[*].SubnetId}' \
  --output json
```

ALB Listener를 확인한다.

```bash
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --names "${NAME_PREFIX}-alb" \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

aws elbv2 describe-listeners \
  --load-balancer-arn "$ALB_ARN" \
  --query 'Listeners[*].{Port:Port,Protocol:Protocol,DefaultActions:DefaultActions}' \
  --output table
```

WAF 연결 상태를 확인한다.

```bash
aws wafv2 get-web-acl-for-resource \
  --resource-arn "$ALB_ARN" \
  --region "$AWS_REGION"
```

Security Group 변경 탐지 규칙을 확인한다.

```bash
aws events describe-rule \
  --name "${NAME_PREFIX}-security-group-changes" \
  --region "$AWS_REGION"

aws events list-targets-by-rule \
  --rule "${NAME_PREFIX}-security-group-changes" \
  --region "$AWS_REGION"
```

VPC Endpoint를 확인한다.

```bash
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${NAME_PREFIX}-vpc" \
  --query 'Vpcs[0].VpcId' \
  --output text)

aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'VpcEndpoints[*].{Name:Tags[?Key==`Name`]|[0].Value,Type:VpcEndpointType,Service:ServiceName,State:State,Subnets:SubnetIds,RouteTables:RouteTableIds,Groups:Groups}' \
  --output table
```

## 컴플라이언스 매핑

| 통제 항목 | Terraform 리소스 | 기대 상태 | 증빙 명령어 | 판정 |
| --- | --- | --- | --- | --- |
| 외부 진입점 ALB 제한 | `aws_security_group.alb`, `aws_lb.app` | ALB SG만 승인된 퍼블릭 HTTP/HTTPS CIDR을 허용한다. | SG 및 ALB Listener 점검 | 정상/주의 |
| App 계층 직접 접근 차단 | `aws_security_group.app`, `aws_subnet.app` | App SG 인바운드 출발지는 ALB SG이며, App 서브넷은 Public IP 자동 할당이 꺼져 있다. | SG, 서브넷, EC2 점검 | 정상/위험 |
| DB 계층 격리 | `aws_security_group.db`, `aws_subnet.db`, `aws_route_table.db` | DB SG 출발지는 App SG이며, DB 라우팅 테이블에는 인터넷 기본 라우트가 없다. | SG 및 라우팅 테이블 점검 | 정상/위험 |
| SSH 퍼블릭 노출 차단 | 모든 SG | 퍼블릭 CIDR에서 오는 TCP `22` 인바운드가 없다. | SSH SG 조회 | 정상/위험 |
| WAF 기반 퍼블릭 트래픽 보호 | `aws_wafv2_web_acl.alb`, `aws_wafv2_web_acl_association.alb` | ALB에 Web ACL이 연결되어 있다. | WAF 연결 확인 | 정상/위험 |
| WAF 관리형 규칙 활성화 | `modules/waf` 관리형 규칙 그룹 | AWS 평판, Anonymous IP, Common, Bad Inputs, SQLi, Admin Protection 규칙이 존재한다. | WAF 콘솔 또는 Terraform plan | 정상/주의 |
| 서비스 경로별 Rate 모니터링 | `modules/waf` 사용자 정의 Rate 규칙 | `/auth/`, `/payments/`, `/transactions/`, `/ops/`, `/audit/` count 규칙이 존재한다. | WAF 콘솔 또는 Terraform plan | 정상/주의 |
| Security Group 변경 탐지 | `aws_cloudwatch_event_rule.security_group_changes`, `aws_cloudwatch_event_target.security_group_changes` | SG 생성/삭제 및 인바운드/아웃바운드 규칙 변경이 SNS 알림으로 전달된다. | EventBridge 규칙 및 Target 점검 | 정상/위험 |
| 프라이빗 AWS 서비스 접근 | `aws_vpc_endpoint.s3`, `aws_vpc_endpoint.interface` | S3 Gateway Endpoint와 KMS, Secrets Manager, Logs, SSM Interface Endpoint가 존재한다. | VPC Endpoint 점검 | 정상/주의 |
| Endpoint 접근 제한 | `aws_security_group.vpc_endpoints` | VPCE SG는 App SG에서 오는 `443`만 허용한다. | SG 점검 | 정상/위험 |

## 외부 접근 과다 허용 대응 절차

1. 노출 리소스를 식별한다.
   - ALB SG, App SG, DB SG, VPCE SG, 라우팅 테이블, 서브넷 Public IP 설정, ALB Listener 중 어디에서 노출이 발생했는지 확인한다.
2. 심각도를 분류한다.
   - DB 퍼블릭 접근, SSH 퍼블릭 접근, App 직접 퍼블릭 접근은 `위험`으로 분류한다.
   - ALB HTTP `0.0.0.0/0`은 서비스 정책상 퍼블릭 HTTP를 허용하는 경우 `주의`, 그렇지 않으면 `위험`으로 분류한다.
3. CIDR 범위를 축소한다.
   - 모든 사용자 대상 외부 접근이 필요하지 않다면 `0.0.0.0/0`을 승인된 CIDR 범위로 교체한다.
4. 잘못된 Security Group 규칙을 제거한다.
   - SSH 퍼블릭 규칙을 제거한다.
   - App SG 출발지를 ALB SG로 변경한다.
   - DB SG 출발지를 App SG로 변경한다.
5. ALB Listener를 검토한다.
   - 필요한 `80` 및 `443` Listener만 유지한다.
   - `alb_certificate_arn`이 설정되어 있다면 HTTPS를 우선 사용한다.
6. WAF를 확인한다.
   - Web ACL이 ALB에 연결되어 있는지 확인한다.
   - 관리형 규칙 그룹과 Rate 규칙이 존재하는지 확인한다.
7. Security Group 변경 탐지를 확인한다.
   - EventBridge 규칙 `${NAME_PREFIX}-security-group-changes`가 존재하는지 확인한다.
   - 규칙 Target이 로컬 SNS 알림 Topic인지 확인한다.
8. 점검 명령어를 다시 실행한다.
   - 명령어 출력 결과를 증빙으로 캡처한다.
9. 조치 결과를 기록한다.
   - 조치 전/후 규칙, 담당자, 시간, 잔여 위험을 문서화한다.

## ALB 우회 접근 점검 기준

| 점검 항목 | 정상 기준 | 우회 위험 기준 | 증빙 |
| --- | --- | --- | --- |
| EC2 Public IP | App EC2 인스턴스에 Public IP가 없다. | App EC2에 Public IP가 있다. | `describe-instances` |
| App 서브넷 설정 | App 서브넷 `MapPublicIpOnLaunch`가 `false`이다. | App 서브넷이 Public IP를 자동 할당한다. | `describe-subnets` |
| App SG 인바운드 | App SG `8080` 출발지는 ALB SG만 허용한다. | App SG가 퍼블릭 CIDR 또는 ALB가 아닌 출발지를 허용한다. | `describe-security-groups` |
| DB SG 인바운드 | DB SG `5432` 출발지는 App SG만 허용한다. | DB SG가 퍼블릭 CIDR, ALB SG 또는 승인되지 않은 넓은 VPC 범위를 허용한다. | `describe-security-groups` |
| DB 라우팅 테이블 | DB 라우팅 테이블에는 IGW/NAT 기본 라우트가 없다. | DB 라우팅 테이블에 인터넷 라우팅 가능한 기본 경로가 있다. | `describe-route-tables` |
| ALB WAF | ALB에 WAF가 연결되어 있다. | Public ALB에 Web ACL이 없다. | `get-web-acl-for-resource` |

## 네트워크 접근통제 판정 기준

| 판정 | 기준 | 예시 |
| --- | --- | --- |
| 정상 | 계층 기반 출발지 제한을 따르고 승인된 퍼블릭 진입점만 존재한다. | ALB SG가 `80/443`을 허용하고, App SG는 ALB SG의 `8080`만 허용하며, DB SG는 App SG의 `5432`만 허용한다. |
| 주의 | 외부 노출이 있으나 서비스 정책상 허용 가능하거나 차단 대신 모니터링 중이다. | ALB HTTP `80`이 `0.0.0.0/0`에 열려 있음, WAF Rate 규칙이 `count` 모드임, 중요도가 낮은 프라이빗 경로에 VPC Endpoint가 없음. |
| 위험 | 프라이빗 또는 민감 계층이 직접 접근 가능하거나 보호 통제가 누락되어 있다. | DB SG 퍼블릭 오픈, App SG 퍼블릭 오픈, SSH `22` 오픈, App EC2 Public IP 보유, ALB WAF 미연결. |

## 현재 Terraform 기준선

| 구성 요소 | 현재 기준선 |
| --- | --- |
| ALB SG | `allowed_http_cidr_blocks`에서 오는 `80`, `443`을 허용하고, VPC CIDR로 향하는 `8080` 아웃바운드를 허용한다. |
| App SG | ALB SG에서 오는 `8080`만 허용한다. |
| DB SG | App SG에서 오는 `5432`만 허용한다. |
| VPCE SG | App SG에서 오는 `443`만 허용한다. |
| Public subnets | Internet Gateway로 라우팅되며 `map_public_ip_on_launch = false`이다. |
| App subnets | NAT Gateway를 통해 라우팅되며 `map_public_ip_on_launch = false`이다. |
| DB subnets | Local-only 라우팅 테이블을 사용하며 `map_public_ip_on_launch = false`이다. |
| WAF | AWS 관리형 규칙과 경로별 Rate count 규칙이 ALB에 연결되어 있다. |
| SG 변경 탐지 | EventBridge가 CloudTrail EC2 API 이벤트에서 Security Group 규칙 변경을 탐지하고 SNS 알림으로 전송한다. |
| VPC endpoints | S3 Gateway Endpoint와 KMS, Secrets Manager, Logs, SSM, SSM Messages, EC2 Messages Interface Endpoint로 구성된다. |
