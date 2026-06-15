# Team Evidence Template

이 문서는 5단계 팀 공통 증빙 양식과 PM 리뷰 체크리스트를 정의한다.

## Evidence Collection Form

김동규는 팀 공통 산출물을 아래 형식으로 취합한다.

| Owner | Area | Check command or screen | Normal criteria | Result | Evidence path | Note |
| --- | --- | --- | --- | --- | --- | --- |
| 김동규 | App/ASG | `describe-auto-scaling-groups` | desired/min/max 기준 충족 |  |  |  |
| 김동규 | ALB | `describe-load-balancers`, `curl /health` | ALB active, health 200 |  |  |  |
| 한경윤 | Audit/Monitoring | CloudTrail/EventBridge/SNS evidence | 탐지 및 알림 기준 충족 |  |  |  |
| 임지혁 | Data Protection | RDS/KMS/Secrets evidence | 암호화 및 secret 관리 기준 충족 |  |  |  |
| 윤정우 | Network Control / HTTPS / mTLS | SG/WAF/VPCE evidence, CloudFront/ALB/ACM HTTPS evidence, mTLS candidate evidence | 외부 접근통제, 전송보안, mTLS 적용 구간 검토 기준 충족 |  |  |  |

## PM Review Checklist

| Item | Normal condition | Status |
| --- | --- | --- |
| 팀원별 5단계 문서가 `docs/`에 존재한다. | 각 담당 영역별 문서가 분리되어 있다. |  |
| Terraform plan 결과가 공유되었다. | add/change/destroy 의미가 팀에 설명되어 있다. |  |
| apply 여부가 합의되었다. | 4단계 검증 중인 환경을 임의로 변경하지 않는다. |  |
| 증빙 양식이 통일되었다. | 명령어, 정상 기준, 결과, 캡처 위치가 포함된다. |  |
| 위험 설정이 식별되었다. | Object Lock, destroy, backend, profile 관련 주의사항이 정리되어 있다. |  |
| 발표 자료 흐름이 정리되었다. | 아키텍처, 단계별 구현, 검증, 한계, 개선 순서로 구성한다. |  |

## Duplicate Review Rule

5단계 산출물은 1~4단계 구축 결과를 다시 나열하지 않는다. 각 문서는 다음 중 하나 이상을 포함해야 한다.

- 점검 기준
- 자동 점검 명령어
- 정상, 주의, 위험 판정 기준
- 장애 또는 위반 대응 절차
- 증빙 양식
- 최종 제출 전 확인 기준
