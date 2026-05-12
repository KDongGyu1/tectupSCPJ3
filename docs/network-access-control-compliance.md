# Network Access Control Compliance

This document defines the network access control review criteria for the FinPay Terraform architecture.

## Scope

| Area | Terraform resources | Review purpose |
| --- | --- | --- |
| Security Group | `modules/security_groups` | Verify tier-based access control between ALB, app, DB, and VPC endpoints. |
| WAF | `modules/waf` | Verify public ALB traffic is protected by managed rules and rate monitoring. |
| Change detection | `modules/automation` | Detect Security Group changes through CloudTrail events and EventBridge alerts. |
| VPC Endpoint | `modules/network`, `modules/vpc_endpoints` | Verify private access paths for AWS services and reduce public internet dependency. |
| Subnet and routing | `modules/network` | Verify public, private app, and isolated DB subnet behavior. |

## Network Violation Criteria

| No. | Check item | Normal condition | Violation condition | Severity | Evidence |
| --- | --- | --- | --- | --- | --- |
| 1 | DB Security Group exposure | DB SG allows PostgreSQL `5432` only from App SG. | DB SG allows `0.0.0.0/0`, `::/0`, public CIDR, or ALB SG directly. | Risk | `aws ec2 describe-security-groups` |
| 2 | App Security Group source | App SG allows service port `8080` only from ALB SG. | App SG allows `0.0.0.0/0`, `::/0`, office CIDR, SSH, or direct user access. | Risk | `aws ec2 describe-security-groups` |
| 3 | SSH exposure | No inbound `22` rule exists on ALB, App, DB, or VPCE SG. | TCP `22` is open to any CIDR or non-approved source. | Risk | `aws ec2 describe-security-groups` |
| 4 | Public IP assignment | App and DB subnets use `map_public_ip_on_launch = false`; EC2 app instances have no public IP. | App/DB subnet auto-assigns public IP, or private EC2 has a public IP. | Risk | `aws ec2 describe-subnets`, `aws ec2 describe-instances` |
| 5 | DB subnet routing | DB route table has no `0.0.0.0/0` route to IGW or NAT. | DB subnet has public/default internet route. | Risk | `aws ec2 describe-route-tables` |
| 6 | ALB public exposure | Only ALB SG may allow external HTTP/HTTPS based on service policy. | App or DB tier is externally reachable without ALB. | Risk | SG, route table, EC2 public IP check |
| 7 | WAF association | WAF Web ACL is associated with the public ALB. | ALB has no WAF association. | Risk | `aws wafv2 get-web-acl-for-resource` |
| 8 | VPC Endpoint access | Interface endpoint SG allows `443` only from App SG. | Endpoint SG allows `443` from `0.0.0.0/0` or unrelated SG. | Caution/Risk | `aws ec2 describe-vpc-endpoints`, SG check |
| 9 | ALB listener policy | HTTP `80` is allowed only when accepted by service policy; HTTPS `443` is preferred when ACM is configured. | Public listener exposes unnecessary ports or unreviewed protocols. | Caution | `aws elbv2 describe-listeners` |

## Network Inspection Command Set

Set common variables first.

```bash
export AWS_PROFILE=fintech
export AWS_REGION=ap-northeast-2
export NAME_PREFIX=finpay-dev

aws sts get-caller-identity
```

Check Security Group rules.

```bash
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${NAME_PREFIX}-alb-sg,${NAME_PREFIX}-app-sg,${NAME_PREFIX}-db-sg,${NAME_PREFIX}-vpce-sg" \
  --query 'SecurityGroups[*].{GroupName:GroupName,GroupId:GroupId,Ingress:IpPermissions,Egress:IpPermissionsEgress}' \
  --output json
```

Check if SSH is publicly open.

```bash
aws ec2 describe-security-groups \
  --query 'SecurityGroups[?IpPermissions[?FromPort==`22` && ToPort==`22`]].{GroupName:GroupName,GroupId:GroupId,Ingress:IpPermissions}' \
  --output table
```

Check subnet public IP settings.

```bash
aws ec2 describe-subnets \
  --filters "Name=tag:Project,Values=finpay" \
  --query 'Subnets[*].{Name:Tags[?Key==`Name`]|[0].Value,SubnetId:SubnetId,AZ:AvailabilityZone,MapPublicIpOnLaunch:MapPublicIpOnLaunch,Cidr:CidrBlock}' \
  --output table
```

Check running EC2 public IP assignment.

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=finpay" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`]|[0].Value,InstanceId:InstanceId,SubnetId:SubnetId,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress,State:State.Name}' \
  --output table
```

Check route tables.

```bash
aws ec2 describe-route-tables \
  --filters "Name=tag:Project,Values=finpay" \
  --query 'RouteTables[*].{Name:Tags[?Key==`Name`]|[0].Value,RouteTableId:RouteTableId,Routes:Routes,Associations:Associations[*].SubnetId}' \
  --output json
```

Check ALB listeners.

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

Check WAF association.

```bash
aws wafv2 get-web-acl-for-resource \
  --resource-arn "$ALB_ARN" \
  --region "$AWS_REGION"
```

Check Security Group change detection rule.

```bash
aws events describe-rule \
  --name "${NAME_PREFIX}-security-group-changes" \
  --region "$AWS_REGION"

aws events list-targets-by-rule \
  --rule "${NAME_PREFIX}-security-group-changes" \
  --region "$AWS_REGION"
```

Check VPC endpoints.

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
| External entry point is limited to ALB | `aws_security_group.alb`, `aws_lb.app` | Only ALB SG permits approved public HTTP/HTTPS CIDRs. | SG and ALB listener checks | Normal/Caution |
| App tier cannot be reached directly | `aws_security_group.app`, `aws_subnet.app` | App SG ingress source is ALB SG; app subnet has no public IP auto-assign. | SG, subnet, EC2 checks | Normal/Risk |
| DB tier is isolated | `aws_security_group.db`, `aws_subnet.db`, `aws_route_table.db` | DB SG source is App SG; DB route table has no internet default route. | SG and route table checks | Normal/Risk |
| SSH is not publicly exposed | All SGs | No TCP `22` ingress from public CIDR. | SSH SG query | Normal/Risk |
| WAF protects public traffic | `aws_wafv2_web_acl.alb`, `aws_wafv2_web_acl_association.alb` | ALB has Web ACL association. | WAF association check | Normal/Risk |
| Managed WAF rules are enabled | `modules/waf` managed rule groups | AWS reputation, anonymous IP, common, bad inputs, SQLi, admin protection rules exist. | WAF console or Terraform plan | Normal/Caution |
| Rate monitoring exists by service path | `modules/waf` custom rate rules | `/auth/`, `/payments/`, `/transactions/`, `/ops/`, `/audit/` count rules exist. | WAF console or Terraform plan | Normal/Caution |
| Security Group changes are detected | `aws_cloudwatch_event_rule.security_group_changes`, `aws_cloudwatch_event_target.security_group_changes` | SG create/delete and ingress/egress rule changes are routed to SNS alerts. | EventBridge rule and target checks | Normal/Risk |
| Private AWS service access exists | `aws_vpc_endpoint.s3`, `aws_vpc_endpoint.interface` | S3 Gateway endpoint and interface endpoints for KMS, Secrets Manager, Logs, SSM exist. | VPC endpoint check | Normal/Caution |
| Endpoint access is restricted | `aws_security_group.vpc_endpoints` | VPCE SG allows `443` from App SG only. | SG check | Normal/Risk |

## Excessive External Access Response Procedure

1. Identify the exposed resource.
   - Confirm whether the exposure is on ALB SG, App SG, DB SG, VPCE SG, route table, subnet public IP setting, or ALB listener.
2. Classify severity.
   - DB public access, SSH public access, or App direct public access is `Risk`.
   - ALB HTTP `0.0.0.0/0` is `Caution` when the service policy accepts public HTTP, otherwise `Risk`.
3. Reduce CIDR scope.
   - Replace `0.0.0.0/0` with approved CIDR ranges when external access is not intended for all users.
4. Remove invalid Security Group rules.
   - Remove SSH public rules.
   - Change App SG source to ALB SG.
   - Change DB SG source to App SG.
5. Review ALB listeners.
   - Keep only required `80` and/or `443` listeners.
   - Prefer HTTPS when `alb_certificate_arn` is configured.
6. Verify WAF.
   - Confirm Web ACL is associated with ALB.
   - Confirm managed rule groups and rate rules are present.
7. Verify Security Group change detection.
   - Confirm EventBridge rule `${NAME_PREFIX}-security-group-changes` exists.
   - Confirm the rule target is the local SNS alert topic.
8. Re-run inspection commands.
   - Capture command output as evidence.
9. Record remediation.
   - Document before/after rule, owner, time, and residual risk.

## ALB Bypass Review Criteria

| Check item | Normal condition | Bypass risk condition | Evidence |
| --- | --- | --- | --- |
| EC2 public IP | App EC2 instances have no public IP. | App EC2 has a public IP. | `describe-instances` |
| App subnet setting | App subnet `MapPublicIpOnLaunch` is `false`. | App subnet auto-assigns public IP. | `describe-subnets` |
| App SG ingress | App SG `8080` source is ALB SG only. | App SG allows public CIDR or non-ALB source. | `describe-security-groups` |
| DB SG ingress | DB SG `5432` source is App SG only. | DB SG allows public CIDR, ALB SG, or broad VPC without approval. | `describe-security-groups` |
| DB route table | DB route table has no default route to IGW/NAT. | DB route table has internet-routable default path. | `describe-route-tables` |
| ALB WAF | ALB is associated with WAF. | Public ALB has no Web ACL. | `get-web-acl-for-resource` |

## Network Access Control Judgment Criteria

| Judgment | Criteria | Example |
| --- | --- | --- |
| Normal | Access follows tier-based source restrictions and only approved public entry points exist. | ALB SG allows `80/443`; App SG allows `8080` from ALB SG; DB SG allows `5432` from App SG. |
| Caution | External exposure exists but may be service-policy acceptable or is monitored rather than blocked. | ALB HTTP `80` open to `0.0.0.0/0`; WAF rate rules are `count`; VPC endpoint missing for non-critical private path. |
| Risk | A private or sensitive tier is directly reachable, or protection controls are missing. | DB SG open to public; App SG open to public; SSH `22` open; app EC2 has public IP; ALB has no WAF. |

## Current Terraform Baseline

| Component | Current baseline |
| --- | --- |
| ALB SG | Allows `80` and `443` from `allowed_http_cidr_blocks`; egress `8080` to VPC CIDR. |
| App SG | Allows `8080` from ALB SG only. |
| DB SG | Allows `5432` from App SG only. |
| VPCE SG | Allows `443` from App SG only. |
| Public subnets | Routed to Internet Gateway; `map_public_ip_on_launch = false`. |
| App subnets | Routed through NAT Gateway; `map_public_ip_on_launch = false`. |
| DB subnets | Local-only route table; `map_public_ip_on_launch = false`. |
| WAF | AWS managed rules plus path-specific rate count rules associated with ALB. |
| SG change detection | EventBridge detects Security Group rule changes from CloudTrail EC2 API events and sends them to SNS alerts. |
| VPC endpoints | S3 Gateway endpoint plus KMS, Secrets Manager, Logs, SSM, SSM Messages, EC2 Messages interface endpoints. |
