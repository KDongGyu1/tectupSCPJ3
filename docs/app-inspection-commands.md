# Application Inspection Commands

이 문서는 애플리케이션 계층 자동 점검에 사용할 명령어 세트를 정리한다.

## Common Variables

```powershell
$env:AWS_PROFILE = "default"
$env:AWS_REGION = "ap-northeast-2"
$NamePrefix = "finpay-dev"
```

## AWS Account

```powershell
aws sts get-caller-identity --profile $env:AWS_PROFILE
```

## Terraform State

```powershell
terraform state list | findstr "module.app"
```

## ALB Status

```powershell
aws elbv2 describe-load-balancers `
  --region $env:AWS_REGION `
  --profile $env:AWS_PROFILE `
  --names "$NamePrefix-alb" `
  --query "LoadBalancers[0].{Name:LoadBalancerName,DNSName:DNSName,State:State.Code,Scheme:Scheme,Type:Type}" `
  --output table
```

## Listener Status

```powershell
$AlbArn = aws elbv2 describe-load-balancers `
  --region $env:AWS_REGION `
  --profile $env:AWS_PROFILE `
  --names "$NamePrefix-alb" `
  --query "LoadBalancers[0].LoadBalancerArn" `
  --output text

aws elbv2 describe-listeners `
  --region $env:AWS_REGION `
  --profile $env:AWS_PROFILE `
  --load-balancer-arn $AlbArn `
  --query "Listeners[*].{Port:Port,Protocol:Protocol,DefaultAction:DefaultActions[0].Type}" `
  --output table
```

## Target Group Health

```powershell
$TargetGroups = aws elbv2 describe-target-groups `
  --region $env:AWS_REGION `
  --profile $env:AWS_PROFILE `
  --load-balancer-arn $AlbArn `
  --query "TargetGroups[*].TargetGroupArn" `
  --output text

foreach ($TgArn in $TargetGroups.Split()) {
  aws elbv2 describe-target-health `
    --region $env:AWS_REGION `
    --profile $env:AWS_PROFILE `
    --target-group-arn $TgArn `
    --query "TargetHealthDescriptions[*].{Target:Target.Id,Port:Target.Port,State:TargetHealth.State,Reason:TargetHealth.Reason}" `
    --output table
}
```

## Auto Scaling Group

```powershell
aws autoscaling describe-auto-scaling-groups `
  --region $env:AWS_REGION `
  --profile $env:AWS_PROFILE `
  --query "AutoScalingGroups[?contains(AutoScalingGroupName, '$NamePrefix')].{Name:AutoScalingGroupName,Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Instances:Instances[*].InstanceId}" `
  --output table
```

## Scaling Activity

```powershell
aws autoscaling describe-scaling-activities `
  --region $env:AWS_REGION `
  --profile $env:AWS_PROFILE `
  --auto-scaling-group-name "$NamePrefix-payment-asg" `
  --max-items 10 `
  --output table
```

## EC2 Public IP Check

```powershell
aws ec2 describe-instances `
  --region $env:AWS_REGION `
  --profile $env:AWS_PROFILE `
  --filters "Name=tag:Name,Values=$NamePrefix-*" "Name=instance-state-name,Values=pending,running,stopping,stopped" `
  --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,InstanceId:InstanceId,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress,State:State.Name,SubnetId:SubnetId}" `
  --output table
```

## SSM Agent Registration

```powershell
aws ssm describe-instance-information `
  --region $env:AWS_REGION `
  --profile $env:AWS_PROFILE `
  --query "InstanceInformationList[*].{InstanceId:InstanceId,PingStatus:PingStatus,Platform:PlatformName,AgentVersion:AgentVersion}" `
  --output table
```

## Health Endpoint

```powershell
$AlbDns = terraform output -raw alb_dns_name
curl "http://$AlbDns/health"
```
