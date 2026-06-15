# Network Transport Security

이 문서는 FinPay dev 환경의 네트워크/전송보안 구현 상태와 심화 개선 후보를 정리한다.

## Current Traffic Paths

| 구간 | 현재 코드 기준 상태 | 현재 판단 | 관련 파일 |
| --- | --- | --- | --- |
| 사용자 -> CloudFront | CloudFront `viewer_protocol_policy = "redirect-to-https"`, 선택적 Viewer mTLS | HTTPS 리다이렉트 적용, mTLS 활성화 시 클라이언트 인증서 요구 | `modules/app/main.tf`, `scripts/cloudfront-viewer-mtls.sh` |
| 사용자 -> ALB | ALB HTTP 80 listener는 기본 forward. HTTPS 443 listener는 `enable_https_listener`와 ACM ARN이 있을 때 생성 | HTTP 직접 접근 가능. HTTPS는 조건부 구현 | `modules/app/main.tf`, `variables.tf` |
| CloudFront -> ALB | 기본값은 `http-only`. `enable_cloudfront_origin_https=true`, HTTPS listener, ALB ACM ARN, `cloudfront_origin_domain_name`이 준비되면 `https-only` | 조건부 HTTPS 전환 가능 | `modules/app/main.tf` |
| ALB -> App | Target Group protocol `HTTP`, port `8080` | 내부 HTTP 구간. 심화 개선 후보 | `modules/app/main.tf` |
| App -> RDS | App 환경변수 `RDS_SSLMODE` 기본값 `require` | PostgreSQL TLS 요구 옵션 반영 | `app/server.py`, `modules/app/user_data.sh.tftpl` |

## HTTPS Implementation Controls

| 변수 | 기본값 | 역할 |
| --- | --- | --- |
| `acm_certificate_arn` | `""` | ALB HTTPS listener에 사용할 ACM 인증서 ARN. 설정 시 `alb_certificate_arn`보다 우선한다. |
| `enable_https_listener` | `false` | ACM 인증서가 있을 때 ALB HTTPS 443 listener 생성을 허용한다. |
| `enable_http_redirect` | `false` | HTTPS listener가 있을 때 ALB HTTP 80 요청을 HTTPS로 리다이렉트한다. |
| `enable_cloudfront_origin_https` | `false` | HTTPS listener가 있을 때 CloudFront -> ALB 구간을 `https-only`로 전환한다. |
| `cloudfront_origin_domain_name` | `""` | CloudFront Origin으로 사용할 ALB 별칭 도메인. ALB 인증서 SAN과 일치해야 한다. |
| `cloudfront_aliases` | `[]` | 사용자 접속용 CloudFront 커스텀 도메인 목록. |
| `cloudfront_acm_certificate_arn` | `""` | CloudFront 커스텀 도메인에 사용할 us-east-1 ACM 인증서 ARN. |
| `enable_cloudfront_viewer_mtls` | `false` | Client -> CloudFront 구간에서 Viewer mTLS를 활성화한다. |
| `cloudfront_viewer_mtls_mode` | `"required"` | 클라이언트 인증서를 필수로 요구할지(`required`) 요청만 할지(`optional`) 지정한다. |
| `cloudfront_viewer_mtls_ca_bundle_path` | `"certs/mtls/client-ca-bundle.pem"` | CloudFront Trust Store에 업로드할 로컬 CA bundle 경로. |
| `rds_sslmode` | `"require"` | App -> RDS PostgreSQL 연결의 TLS 요구 수준을 지정한다. |

## mTLS Candidate Segments

| 후보 구간 | 적용 가능성 | 장점 | 구현 난이도 | 현재 프로젝트 판단 |
| --- | --- | --- | --- | --- |
| Client -> CloudFront | 가능 | 실제 사용자 진입점에서 클라이언트 인증서 검증 | 중간 | `enable_cloudfront_viewer_mtls=true`로 구현 가능. Terraform AWS provider가 아직 ViewerMtlsConfig를 직접 다루지 않아 AWS CLI 보조 스크립트를 사용한다. |
| ALB -> App | 가능 | ALB와 App 사이의 서비스 신원 검증 강화 | 높음 | 현재 App은 단순 Python HTTP 서버와 ALB Target Group으로 구성되어 있어 바로 적용하지 않는다. ACM Private CA, Nginx/Envoy sidecar, 또는 ALB mutual authentication 지원 범위 검토가 필요하다. |
| App -> 내부 서비스 | 가능 | 내부 API 호출 시 서비스 간 인증 강화 | 중간~높음 | 현재 내부 마이크로서비스 간 호출 구조가 코드상 명확하지 않으므로 설계 후보로 남긴다. 향후 service mesh 또는 sidecar TLS로 검토한다. |
| 관리자 접근 구간 `/ops/*` | 가능 | 운영자 기능 접근에 강한 클라이언트 인증 추가 | 중간 | 현재 Cognito/RBAC 중심 구조이므로 mTLS는 추가 방어 계층으로 분류한다. CloudFront/ALB 앞단 인증서 기반 접근 통제 PoC가 필요하다. |

## CloudFront Viewer mTLS Implementation

현재 구현은 다음 흐름이다.

```text
Client certificate
  -> CloudFront Viewer mTLS
  -> CloudFront Trust Store
  -> ALB HTTPS
  -> App
```

Terraform은 CA bundle을 전용 S3 버킷에 업로드한다. 이후 `scripts/cloudfront-viewer-mtls.sh`가 CloudFront Trust Store를 만들거나 갱신하고, 배포의 `ViewerMtlsConfig`를 설정한다. 이 보조 스크립트를 쓰는 이유는 현재 저장소의 Terraform AWS provider `5.100.0`이 CloudFront `ViewerMtlsConfig` 블록을 네이티브로 제공하지 않기 때문이다.

테스트용 CA와 클라이언트 인증서는 아래 명령으로 만든다.

```bash
./scripts/generate-viewer-mtls-certs.sh
```

적용 후 확인 명령은 다음과 같다.

```bash
aws cloudfront get-distribution-config \
  --id "$(terraform output -raw cloudfront_distribution_id)" \
  --query "DistributionConfig.ViewerMtlsConfig"

curl -v https://app.finpay-sec.p-e.kr/health

curl -v \
  --cert certs/mtls/client.crt \
  --key certs/mtls/client.key \
  https://app.finpay-sec.p-e.kr/health
```

mTLS가 `required`이면 첫 번째 `curl`은 클라이언트 인증서가 없어 실패해야 하고, 두 번째 `curl`은 신뢰된 CA가 서명한 클라이언트 인증서를 사용하므로 성공해야 한다.

## Deferred Design Items

| 항목 | 설계 제안으로 남기는 이유 | 향후 구현 방향 |
| --- | --- | --- |
| ALB -> App mTLS | App 서버 인증서 발급/배포/회전 구조가 필요하고 운영 복잡도가 높다. | ACM Private CA 또는 사설 CA를 정하고, sidecar 또는 앱 내 TLS 종단 방식을 선택한다. |
| CloudFront 전용 WAF | CloudFront scope WAF는 `us-east-1` 리소스이며 비용과 운영 정책 검토가 필요하다. | `enable_cloudfront_waf` 같은 조건부 변수와 별도 WebACL 구성을 검토한다. |
| Route 53 + Custom Domain + ACM | 외부 DNS 제공자를 사용할 경우 Terraform이 DNS 검증 레코드를 자동 생성하지 못할 수 있다. | DNS 제공자에 CloudFront alias, ALB origin alias, ACM 검증 CNAME을 수동 등록한 뒤 Terraform 변수에 ARN과 도메인을 반영한다. |
| AWS Config 상시 평가 | 비용과 계정 서비스 활성화 제약이 있을 수 있다. | `enable_aws_config=true` 전환 후 핵심 Managed Rule부터 적용한다. |

## Verification Commands

```bash
aws elbv2 describe-listeners \
  --region ap-northeast-2 \
  --load-balancer-arn "$ALB_ARN"

aws elbv2 describe-target-groups \
  --region ap-northeast-2 \
  --load-balancer-arn "$ALB_ARN"

aws cloudfront get-distribution-config \
  --id "$CLOUDFRONT_DISTRIBUTION_ID"

DISTRIBUTION_ID="$CLOUDFRONT_DISTRIBUTION_ID" \
  scripts/cloudfront-viewer-mtls.sh status

rg -n "RDS_SSLMODE|sslmode" app/server.py modules/app/user_data.sh.tftpl
```

## Summary Judgment

- 사용자 -> CloudFront HTTPS 리다이렉트는 구현되어 있고, 선택적으로 Viewer mTLS를 요구할 수 있다.
- ALB HTTPS, ALB HTTP redirect, CloudFront -> ALB HTTPS는 ACM 인증서와 DNS 별칭이 있을 때 조건부로 활성화할 수 있다.
- App -> RDS는 `RDS_SSLMODE=require` 기본값으로 TLS 요구 옵션을 반영했다.
- ALB -> App mTLS와 내부 서비스 mTLS는 현재 구조에서는 설계 후보로 남긴다.
