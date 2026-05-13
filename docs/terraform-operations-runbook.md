# Terraform Operations Runbook

이 문서는 Terraform 실행 표준 절차와 배포 실패 대응 절차를 정의한다.

## Execution Standard

Terraform 작업은 repository root에서 실행한다.

```powershell
cd C:\project\tectupSCPJ3
terraform init -reconfigure -backend-config=backend-dev.hcl
terraform fmt -check
terraform validate
terraform plan
```

`terraform apply`는 plan 결과를 팀원에게 공유한 뒤 실행한다.

```powershell
terraform apply
terraform output
```

## Plan Review Criteria

| Check item | Normal | Caution | Risk |
| --- | --- | --- | --- |
| Backend | `backend-dev.hcl`의 bucket, key, region, profile이 팀 기준과 일치한다. | profile만 로컬 환경에 맞게 다르지만 같은 AWS account와 같은 state를 본다. | 다른 bucket, key, region을 보거나 local state로 전환된다. |
| Plan result | 기존 환경에서 `0 add, 0 change, 0 destroy` 또는 의도한 변경만 표시된다. | Launch Template 등 앱 배포 변경이 일부 표시된다. | 의도하지 않은 대량 add, destroy, replacement가 표시된다. |
| State | `terraform state list`에서 기존 리소스가 조회된다. | 일부 리소스에 drift가 있다. | state가 비어 있거나 실제 AWS 리소스와 불일치한다. |
| Local files | `tfplan`은 로컬 검토용으로만 사용한다. | 임시 plan 파일이 있지만 커밋 대상에는 없다. | `tfplan`, `destroy.tfplan`, `*.tfstate`가 커밋 대상에 포함된다. |

## Failure Response Runbook

| Symptom | First check | Likely cause | Response |
| --- | --- | --- | --- |
| `terraform plan`이 대량 add를 표시한다. | `terraform state list`, `backend-dev.hcl` | 다른 backend/state를 보고 있거나 destroy 후 state가 비어 있다. | `terraform init -reconfigure -backend-config=backend-dev.hcl` 후 state와 실제 AWS 리소스를 비교한다. |
| state lock 오류가 발생한다. | lock ID, 실행 중인 Terraform 프로세스 | 이전 plan/apply가 lock을 남겼다. | 다른 실행이 없는지 확인 후 `terraform force-unlock <LOCK_ID>`를 사용한다. |
| backend 설정 오류가 발생한다. | `backend-dev.hcl`, `terraform init` 출력 | bucket, key, region, profile 불일치 | backend 파일을 팀 기준과 맞추고 `terraform init -reconfigure -backend-config=backend-dev.hcl`을 재실행한다. |
| AWS profile 오류가 발생한다. | `aws sts get-caller-identity --profile <profile>` | profile 미설정 또는 다른 account 사용 | 팀 기준 account인지 확인하고 `backend-dev.hcl`과 provider profile을 맞춘다. |
| ALB DNS가 NXDOMAIN이다. | `terraform output -raw alb_dns_name` | 이전 ALB DNS를 사용하거나 ALB가 재생성되었다. | 최신 output의 DNS로 다시 접속한다. |
| Target Group이 unhealthy이다. | `describe-target-health` | app service 미기동, security group, user data 실패 | ASG activity, EC2 system log, SSM 접속 상태를 순서대로 확인한다. |
| ASG instance가 생성되지 않는다. | `describe-scaling-activities` | Launch Template, IAM instance profile, subnet capacity, account limit 문제 | scaling activity의 status message를 기준으로 조치한다. |
| SSM에 instance가 안 보인다. | `describe-instance-information` | SSM Agent 미기동, IAM role, endpoint 문제 | user data의 SSM Agent 설치 블록, `AmazonSSMManagedInstanceCore`, SSM endpoint를 확인한다. |
| S3 Object Lock 삭제 오류가 난다. | plan의 destroy/replacement 항목 | 중앙 로그 버킷 삭제 또는 교체 시도 | 로그 버킷 이름 변경 여부를 확인하고, Object Lock 버킷은 삭제 대상에서 제외한다. |
