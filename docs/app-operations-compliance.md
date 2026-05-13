# Application Operations Compliance

이 문서는 김동규 담당 5단계 산출물의 진입점이다. 1~4단계에서 이미 구축한 ALB, Target Group, Launch Template, Auto Scaling Group, EC2를 다시 구축하거나 단순 재확인하는 것이 아니라, 운영 중 반복 사용할 실행 표준, 자동 점검 기준, 장애 대응 절차, 팀 공통 증빙 양식을 정리한다.

## Deliverable Mapping

| No. | 5단계 할 일 | 세부 문서 | 완료 기준 |
| --- | --- | --- | --- |
| 1 | Terraform 실행 표준 절차 작성 | [Terraform Operations Runbook](terraform-operations-runbook.md) | 팀원이 같은 순서로 init, fmt, validate, plan, apply, output을 수행할 수 있다. |
| 2 | 배포 실패 대응 절차 작성 | [Terraform Operations Runbook](terraform-operations-runbook.md) | state lock, backend, profile, Object Lock, ALB DNS, ASG 문제별 1차 대응이 정리되어 있다. |
| 3 | 앱 계층 자동 점검 명령어 세트 작성 | [Application Inspection Commands](app-inspection-commands.md) | ALB, Listener, Target Group, ASG, EC2, SSM, health endpoint 점검 명령어가 있다. |
| 4 | Terraform 운영 변수 허용 기준 정리 | [Application Runtime Standards](app-runtime-standards.md) | 앱 운영 변수별 정상, 주의, 위험 기준이 구분되어 있다. |
| 5 | 배포 산출물 취합 양식 작성 | [Team Evidence Template](team-evidence-template.md) | 담당자, 점검 항목, 명령어, 정상 기준, 결과, 증빙 위치를 기록할 수 있다. |
| 6 | 팀 전체 5단계 결과 취합 및 중복 제거 | [Team Evidence Template](team-evidence-template.md) | 팀원별 산출물 확인과 중복 제거 기준이 있다. |

## Scope

| Area | Terraform resources | Review purpose |
| --- | --- | --- |
| Terraform execution | repository root, `backend-dev.hcl` | 모든 팀원이 같은 remote state 기준으로 작업하도록 표준 실행 절차를 정의한다. |
| Application capacity | `modules/app.aws_autoscaling_group.app` | ASG 용량 값이 운영 기준을 벗어나지 않는지 판정한다. |
| Application routing | `modules/app.aws_lb`, `aws_lb_listener`, `aws_lb_target_group` | ALB DNS, listener, target group 상태 점검을 표준화한다. |
| Instance bootstrap | `modules/app.aws_launch_template.app` | Launch Template, user data, SSM Agent, IMDSv2 기준을 운영 체크 항목으로 관리한다. |
| Failure response | Terraform CLI, AWS CLI | state lock, backend, profile, ALB DNS, ASG 미기동 문제의 대응 절차를 정리한다. |
| Team evidence | `docs/` | 팀원별 증빙 자료 형식을 통일하고 5단계 결과를 취합한다. |

## Document Set

| 문서 | 목적 |
| --- | --- |
| [terraform-operations-runbook.md](terraform-operations-runbook.md) | Terraform 실행 순서, plan 검토 기준, 배포 실패 대응 절차를 정리한다. |
| [app-runtime-standards.md](app-runtime-standards.md) | 앱 계층 운영 변수, Object Lock 개발/최종 정책 기준을 정리한다. |
| [app-inspection-commands.md](app-inspection-commands.md) | 앱 계층 자동 점검용 AWS CLI 명령어를 정리한다. |
| [team-evidence-template.md](team-evidence-template.md) | 팀 공통 증빙 양식과 PM 리뷰 체크리스트를 정리한다. |

## Current Status

| Item | Status |
| --- | --- |
| 김동규 개인 5단계 문서 | 완료 |
| 팀 공통 증빙 양식 | 준비 완료 |
| 팀 전체 최종 취합 | 팀원 산출물 수신 후 진행 |
| 개발 단계 Object Lock 정책 | 반복 apply/destroy를 위해 기본 retention rule 비활성 유지 |
| 최종 단계 Object Lock 정책 | 최종 검증 시 `enable_log_object_lock = true` 전환 필요 |
