# Network Access Control Compliance

이 문서는 FinPay Terraform architecture의 network access control review criteria를 정의한다.

## Scope

| Area | Terraform resources | Review purpose |
| --- | --- | --- |
| Security Group | `modules/security_groups` | ALB, App, DB, VPC Endpoint 간 tier-based access control이 적용되어 있는지 확인한다. |
| WAF | `modules/waf` | Public ALB traffic이 managed rules와 rate monitoring으로 보호되는지 확인한다. |
| Change detection | `modules/automation` | CloudTrail events와 EventBridge alerts를 통해 Security Group 변경을 탐지한다. |
| VPC Endpoint | `modules/network`, `modules/vpc_endpoints` | AWS services 접근 경로가 private access path로 구성되어 있고 public internet dependency가 줄어드는지 확인한다. |
| Subnet and routing | `modules/network` | public, private app, isolated DB subnet 동작을 확인한다. |

## Network Violation Criteria

| No. | Check item | Normal condition | Violation condition | Severity | Evidence |
| --- | --- | --- | --- | --- | --- |
| 1 | DB Security Group exposure | DB SG는 App SG에서 오는 PostgreSQL `5432`만 허용한다. | DB SG가 `0.0.0.0/0`, `::/0`, public CIDR 또는 ALB SG direct access를 허용한다. | Risk | `aws ec2 describe-security-groups` |
| 2 | App Security Group source | App SG는 ALB SG에서 오는 service port `8080`만 허용한다. | App SG가 `0.0.0.0/0`, `::/0`, office CIDR, SSH 또는 direct user access를 허용한다. | Risk | `aws ec2 describe-security-groups` |
| 3 | SSH exposure | ALB, App, DB, VPCE SG에 inbound `22` rule이 없어야 한다. | TCP `22`가 any CIDR 또는 non-approved source에 열려 있다. | Risk | `aws ec2 describe-security-groups` |
| 4 | Public IP assignment | App 및 DB subnets는 `map_public_ip_on_launch = false`이고, EC2 app instances는 Public IP가 없어야 한다. | App/DB subnet이 Public IP를 auto-assign하거나 private EC2에 Public IP가 있다. | Risk | `aws ec2 describe-subnets`, `aws ec2 describe-instances` |
| 5 | DB subnet routing | DB route table에는 IGW 또는 NAT로 향하는 `0.0.0.0/0` route가 없어야 한다. | DB subnet에 public/default internet route가 있다. | Risk | `aws ec2 describe-route-tables` |
| 6 | ALB public exposure | 외부 HTTP/HTTPS 접근 허용은 service policy에 따라 ALB SG에만 허용한다. | App 또는 DB tier가 ALB를 거치지 않고 externally reachable 상태이다. | Risk | SG, route table, EC2 Public IP check |
| 7 | WAF association | WAF Web ACL이 public ALB에 연결되어 있어야 한다. | ALB에 WAF association이 없다. | Risk | `aws wafv2 get-web-acl-for-resource` |
| 8 | VPC Endpoint access | Interface endpoint SG는 App SG에서 오는 `443`만 허용한다. | Endpoint SG가 `0.0.0.0/0` 또는 unrelated SG에서 오는 `443`을 허용한다. | Caution/Risk | `aws ec2 describe-vpc-endpoints`, SG check |
| 9 | ALB listener policy | HTTP `80`은 service policy상 허용될 때만 사용하고, ACM 설정 시 HTTPS `443`을 우선한다. | Public listener가 unnecessary ports 또는 unreviewed protocols를 노출한다. | Caution | `aws elbv2 describe-listeners` |

## Network Inspection Command Set

먼저 common variables를 설정한다.

```bash
export AWS_PROFILE=fintech
export AWS_REGION=ap-northeast-2
export NAME_PREFIX=finpay-dev

aws sts get-caller-identity
```

Security Group rules를 확인한다.

```bash
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${NAME_PREFIX}-alb-sg,${NAME_PREFIX}-app-sg,${NAME_PREFIX}-db-sg,${NAME_PREFIX}-vpce-sg" \
  --query 'SecurityGroups[*].{GroupName:GroupName,GroupId:GroupId,Ingress:IpPermissions,Egress:IpPermissionsEgress}' \
  --output json
```

SSH가 publicly open 상태인지 확인한다.

```bash
aws ec2 describe-security-groups \
  --query 'SecurityGroups[?IpPermissions[?FromPort==`22` && ToPort==`22`]].{GroupName:GroupName,GroupId:GroupId,Ingress:IpPermissions}' \
  --output table
```

Subnet public IP settings를 확인한다.

```bash
aws ec2 describe-subnets \
  --filters "Name=tag:Project,Values=finpay" \
  --query 'Subnets[*].{Name:Tags[?Key==`Name`]|[0].Value,SubnetId:SubnetId,AZ:AvailabilityZone,MapPublicIpOnLaunch:MapPublicIpOnLaunch,Cidr:CidrBlock}' \
  --output table
```

Running EC2 public IP assignment를 확인한다.

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=finpay" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`]|[0].Value,InstanceId:InstanceId,SubnetId:SubnetId,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress,State:State.Name}' \
  --output table
```

Route tables를 확인한다.

```bash
aws ec2 describe-route-tables \
  --filters "Name=tag:Project,Values=finpay" \
  --query 'RouteTables[*].{Name:Tags[?Key==`Name`]|[0].Value,RouteTableId:RouteTableId,Routes:Routes,Associations:Associations[*].SubnetId}' \
  --output json
```

ALB listeners를 확인한다.

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

WAF association을 확인한다.

```bash
aws wafv2 get-web-acl-for-resource \
  --resource-arn "$ALB_ARN" \
  --region "$AWS_REGION"
```

Security Group change detection rule을 확인한다.

```bash
aws events describe-rule \
  --name "${NAME_PREFIX}-security-group-changes" \
  --region "$AWS_REGION"

aws events list-targets-by-rule \
  --rule "${NAME_PREFIX}-security-group-changes" \
  --region "$AWS_REGION"
```

VPC endpoints를 확인한다.

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

## Compliance Mapping

| Control item | Terraform resource | Expected state | Evidence command | Judgment |
| --- | --- | --- | --- | --- |
| External entry point is limited to ALB | `aws_security_group.alb`, `aws_lb.app` | ALB SG만 approved public HTTP/HTTPS CIDRs를 허용한다. | SG and ALB listener checks | Normal/Caution |
| App tier cannot be reached directly | `aws_security_group.app`, `aws_subnet.app` | App SG ingress source는 ALB SG이며, app subnet은 public IP auto-assign이 꺼져 있다. | SG, subnet, EC2 checks | Normal/Risk |
| DB tier is isolated | `aws_security_group.db`, `aws_subnet.db`, `aws_route_table.db` | DB SG source는 App SG이며, DB route table에는 internet default route가 없다. | SG and route table checks | Normal/Risk |
| SSH is not publicly exposed | All SGs | public CIDR에서 오는 TCP `22` ingress가 없다. | SSH SG query | Normal/Risk |
| WAF protects public traffic | `aws_wafv2_web_acl.alb`, `aws_wafv2_web_acl_association.alb` | ALB에 Web ACL association이 있다. | WAF association check | Normal/Risk |
| Managed WAF rules are enabled | `modules/waf` managed rule groups | AWS reputation, anonymous IP, common, bad inputs, SQLi, admin protection rules가 존재한다. | WAF console or Terraform plan | Normal/Caution |
| Rate monitoring exists by service path | `modules/waf` custom rate rules | `/auth/`, `/payments/`, `/transactions/`, `/ops/`, `/audit/` count rules가 존재한다. | WAF console or Terraform plan | Normal/Caution |
| Security Group changes are detected | `aws_cloudwatch_event_rule.security_group_changes`, `aws_cloudwatch_event_target.security_group_changes` | SG create/delete 및 ingress/egress rule changes가 SNS alerts로 전달된다. | EventBridge rule and target checks | Normal/Risk |
| Private AWS service access exists | `aws_vpc_endpoint.s3`, `aws_vpc_endpoint.interface` | S3 Gateway endpoint와 KMS, Secrets Manager, Logs, SSM interface endpoints가 존재한다. | VPC endpoint check | Normal/Caution |
| Endpoint access is restricted | `aws_security_group.vpc_endpoints` | VPCE SG는 App SG에서 오는 `443`만 허용한다. | SG check | Normal/Risk |

## Excessive External Access Response Procedure

1. Identify the exposed resource.
   - ALB SG, App SG, DB SG, VPCE SG, route table, subnet public IP setting, ALB listener 중 어디에서 노출이 발생했는지 확인한다.
2. Classify severity.
   - DB public access, SSH public access, App direct public access는 `Risk`로 분류한다.
   - ALB HTTP `0.0.0.0/0`은 service policy상 public HTTP를 허용하는 경우 `Caution`, 그렇지 않으면 `Risk`로 분류한다.
3. Reduce CIDR scope.
   - 모든 사용자 대상 external access가 필요하지 않다면 `0.0.0.0/0`을 approved CIDR ranges로 교체한다.
4. Remove invalid Security Group rules.
   - SSH public rules를 제거한다.
   - App SG source를 ALB SG로 변경한다.
   - DB SG source를 App SG로 변경한다.
5. Review ALB listeners.
   - 필요한 `80` 및 `443` listeners만 유지한다.
   - `alb_certificate_arn`이 설정되어 있다면 HTTPS를 우선 사용한다.
6. Verify WAF.
   - Web ACL이 ALB에 연결되어 있는지 확인한다.
   - managed rule groups와 rate rules가 존재하는지 확인한다.
7. Verify Security Group change detection.
   - EventBridge rule `${NAME_PREFIX}-security-group-changes`가 존재하는지 확인한다.
   - rule target이 local SNS alert topic인지 확인한다.
8. Re-run inspection commands.
   - command output을 evidence로 캡처한다.
9. Record remediation.
   - before/after rule, owner, time, residual risk를 문서화한다.

## ALB Bypass Review Criteria

| Check item | Normal condition | Bypass risk condition | Evidence |
| --- | --- | --- | --- |
| EC2 public IP | App EC2 instances에 Public IP가 없다. | App EC2에 Public IP가 있다. | `describe-instances` |
| App subnet setting | App subnet `MapPublicIpOnLaunch`가 `false`이다. | App subnet이 Public IP를 auto-assign한다. | `describe-subnets` |
| App SG ingress | App SG `8080` source는 ALB SG만 허용한다. | App SG가 public CIDR 또는 non-ALB source를 허용한다. | `describe-security-groups` |
| DB SG ingress | DB SG `5432` source는 App SG만 허용한다. | DB SG가 public CIDR, ALB SG 또는 승인되지 않은 broad VPC를 허용한다. | `describe-security-groups` |
| DB route table | DB route table에는 IGW/NAT로 향하는 default route가 없다. | DB route table에 internet-routable default path가 있다. | `describe-route-tables` |
| ALB WAF | ALB에 WAF가 연결되어 있다. | Public ALB에 Web ACL이 없다. | `get-web-acl-for-resource` |

## Network Access Control Judgment Criteria

| Judgment | Criteria | Example |
| --- | --- | --- |
| Normal | tier-based source restrictions를 따르고 approved public entry points만 존재한다. | ALB SG가 `80/443`을 허용하고, App SG는 ALB SG의 `8080`만 허용하며, DB SG는 App SG의 `5432`만 허용한다. |
| Caution | external exposure가 있으나 service-policy상 허용 가능하거나 block 대신 monitoring 중이다. | ALB HTTP `80`이 `0.0.0.0/0`에 열려 있음, WAF rate rules가 `count` 모드임, non-critical private path에 VPC endpoint가 없음. |
| Risk | private 또는 sensitive tier가 직접 접근 가능하거나 protection controls가 누락되어 있다. | DB SG public open, App SG public open, SSH `22` open, app EC2 Public IP 보유, ALB WAF 미연결. |

## Current Terraform Baseline

| Component | Current baseline |
| --- | --- |
| ALB SG | `allowed_http_cidr_blocks`에서 오는 `80`, `443`을 허용하고, VPC CIDR로 향하는 `8080` egress를 허용한다. |
| App SG | ALB SG에서 오는 `8080`만 허용한다. |
| DB SG | App SG에서 오는 `5432`만 허용한다. |
| VPCE SG | App SG에서 오는 `443`만 허용한다. |
| Public subnets | Internet Gateway로 라우팅되며 `map_public_ip_on_launch = false`이다. |
| App subnets | NAT Gateway를 통해 라우팅되며 `map_public_ip_on_launch = false`이다. |
| DB subnets | Local-only route table을 사용하며 `map_public_ip_on_launch = false`이다. |
| WAF | AWS managed rules와 path-specific rate count rules가 ALB에 연결되어 있다. |
| SG change detection | EventBridge가 CloudTrail EC2 API events에서 Security Group rule changes를 탐지하고 SNS alerts로 전송한다. |
| VPC endpoints | S3 Gateway endpoint와 KMS, Secrets Manager, Logs, SSM, SSM Messages, EC2 Messages interface endpoints로 구성된다. |
