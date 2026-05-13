# Application Runtime Standards

이 문서는 애플리케이션 계층 운영 변수와 개발/최종 단계의 로그 보존 정책 기준을 정의한다.

## Operating Variable Standards

| Variable | Current baseline | Normal | Caution | Risk |
| --- | --- | --- | --- | --- |
| `app_instance_type` | `t3.micro` | 실습/개발 환경 비용 기준에 맞는다. | 성능 테스트 목적의 일시적 상향이다. | 사유 없이 고비용 인스턴스로 변경된다. |
| `app_desired_capacity` | `1` per service | 각 서비스별 최소 1대가 유지된다. | 비용 절감을 위해 일시적으로 0으로 낮춘다. | 0으로 유지되어 서비스 검증이 불가능하다. |
| `app_min_size` | `1` | ASG가 최소 1대를 유지한다. | 테스트 목적의 임시 0 설정이다. | 운영 기준 없이 0으로 고정된다. |
| `app_max_size` | `2` | desired보다 크거나 같고 비용 범위 안에 있다. | 부하 테스트 목적의 일시적 상향이다. | 계정 한도와 비용 검토 없이 크게 증가한다. |
| `alb_certificate_arn` | empty | HTTP 데모 환경에서는 비어 있을 수 있다. | HTTPS 적용 전 준비 상태다. | HTTPS 필수 환경인데 인증서 없이 운영한다. |
| `enable_alb_access_logs` | `false` | 현재 중앙 로그 버킷 제약을 고려해 비활성화한다. | 별도 ALB 로그 전용 버킷을 준비 중이다. | Object Lock/KMS 정책을 검토하지 않고 활성화한다. |
| `enable_log_object_lock` | `false` during dev | 반복 apply/destroy 단계에서는 false로 두어 로그 버킷 삭제 실패를 방지한다. | 최종 검증 직전에 true 전환 계획이 문서화되어 있다. | 최종 제출 단계에서도 false로 남아 감사 로그 보존 기준을 충족하지 못한다. |

## Dev And Finalization Policy

현재 프로젝트는 4단계 검증과 5단계 문서화 과정에서 반복적으로 `terraform apply`와 `terraform destroy`를 수행한다. 이 기간에는 중앙 로그 S3 버킷의 기본 Object Lock retention rule을 끈 상태로 유지한다.

개발 반복 단계 기준:

- `enable_log_object_lock = false`를 유지한다.
- `force_destroy = true`인 중앙 로그 버킷 삭제 흐름을 허용한다.
- Object Lock 기본 retention rule이 제거되는 plan은 개발 반복 목적이라면 허용할 수 있다.
- 이 판단은 최종 운영 기준이 아니라 개발 편의 기준으로 기록한다.

최종 마무리 단계 기준:

- `enable_log_object_lock = true`로 전환한다.
- `log_object_lock_retention_days = 365`를 적용한다.
- `terraform plan`에서 S3 bucket replacement 또는 destroy가 없는지 확인한다.
- `aws s3api get-object-lock-configuration`으로 `DefaultRetention`이 `GOVERNANCE`, `Days = 365`인지 확인한다.

최종 확인 명령어:

```powershell
aws s3api get-object-lock-configuration `
  --bucket finpay-dev-logs-064137889010 `
  --region ap-northeast-2 `
  --profile default
```

정상 기준:

```json
{
  "ObjectLockConfiguration": {
    "ObjectLockEnabled": "Enabled",
    "Rule": {
      "DefaultRetention": {
        "Mode": "GOVERNANCE",
        "Days": 365
      }
    }
  }
}
```
