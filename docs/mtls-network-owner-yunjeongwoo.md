# mTLS Network Owner Review

이 문서는 윤정우 담당 네트워크, mTLS 적용 구간 검토 산출물이다. 범위는 mTLS 후보 구간 선정, 통신 경로, SG/포트 변경 영향, 비정상 인증서 차단 테스트 관점의 검토이며, 기준일은 2026-06-09이다.

## 1. 담당 목표

2단계 HTTPS 전환 이후 추가 인증 강화를 위해 mTLS 적용 가능 구간을 검토한다. 이번 단계의 윤정우 역할은 전체 구현 단독 수행이 아니라, PoC 적용 구간 선정과 네트워크 접근통제 영향 검토에 둔다.

현재 운영 진입점은 ALB가 아니라 CloudFront이다.

```text
Client -> CloudFront -> ALB -> App
```

따라서 최종 권장 mTLS 적용 구간은 실제 사용자 진입점인 `Client -> CloudFront`이다.

| 구분 | 판단 |
| --- | --- |
| 최종 권장 PoC | Client -> CloudFront Viewer mTLS |
| 대체 PoC 후보 | Client -> ALB mTLS |
| 장기 내부망 보안 후보 | ALB -> App mTLS |
| 제외 구간 | CloudFront -> ALB mTLS |

CloudFront -> ALB 구간은 2단계에서 이미 `https-only`로 전환했고, ALB 직접 접근도 제한하는 방향이므로 mTLS 우선 적용 대상에서 제외한다.

## 2. 현재 구조 근거

| 구간 | 현재 코드 기준 | 판단 | 근거 파일 |
| --- | --- | --- | --- |
| Client -> CloudFront | CloudFront가 사용자 진입점이며 Viewer는 HTTPS redirect | Viewer mTLS 최우선 후보 | `modules/app/main.tf` |
| CloudFront -> ALB | Origin protocol을 `https-only`로 전환 가능 | mTLS 제외, HTTPS와 접근제한으로 보호 | `modules/app/main.tf`, `modules/app/locals.tf` |
| ALB -> App | Target Group protocol `HTTP`, port `8080` | 내부망 mTLS 장기 후보 | `modules/app/main.tf` |
| App SG ingress | ALB SG에서 오는 TCP `8080`만 허용 | App 직접 접근 범위는 ALB로 제한됨 | `modules/security_groups/main.tf` |
| App -> RDS | PostgreSQL `sslmode=require` | TLS 적용 영역, mTLS 대상 아님 | `app/server.py`, `modules/app/user_data.sh.tftpl` |

현재 외부 서비스 주소는 `app.finpay-sec.p-e.kr`이며 CloudFront alias로 연결된다. 따라서 클라이언트 인증서를 요구하는 mTLS는 CloudFront Viewer 구간에 적용하는 것이 운영 구조와 가장 잘 맞는다.

## 3. mTLS 후보 구간 정의서

| 후보 구간 | 적용 가능성 | 장점 | 난이도 | PoC 선정 여부 | 판단 |
| --- | --- | --- | --- | --- | --- |
| Client -> CloudFront Viewer | 가능 | 실제 사용자 진입점에서 인증서 검증, ALB 직접 접근 제한 원칙 유지, App 영향 없음 | 중간 | 최종 권장 | 현재 운영 구조와 가장 일치 |
| Client -> ALB | 가능 | ALB 기본 mTLS 기능 활용, 인증서 없음/오류 차단 증적 확보 쉬움 | 중간 | 대체 후보 | CloudFront를 우회하는 테스트 endpoint가 필요해 운영 구조와는 덜 일치 |
| ALB -> App | 가능 | 현재 남은 내부 HTTP 8080 구간 보호, 내부 Zero Trust 강화 | 높음 | 장기 후보 | 보안 효과는 크지만 health check와 인증서 배포 문제가 큼 |
| App -> App | 조건부 가능 | 서비스 간 신원 검증 가능 | 높음 | 제외 | 현재 앱이 단일 Python 서버 형태라 내부 서비스 간 호출 구조가 명확하지 않음 |
| App -> Internal Service | 조건부 가능 | 내부 API 호출 시 클라이언트 인증 가능 | 높음 | 제외 | 별도 내부 서비스가 현재 Terraform/App 구조에 명시되어 있지 않음 |
| CloudFront -> ALB | 낮음 | Origin 신원 검증 강화 가능 | 높음 | 제외 | 이미 HTTPS와 ALB 직접 접근 제한으로 보호되어 우선순위 낮음 |

최종 PoC 권장 구간은 `Client -> CloudFront Viewer mTLS`이다. 이유는 사용자가 실제로 접근하는 첫 지점이 CloudFront이고, 이 위치에서 클라이언트 인증서를 검증하면 ALB 직접 접근을 다시 열지 않아도 되기 때문이다.

## 4. 권장안 구현 구상: Client -> CloudFront Viewer mTLS

권장안은 CloudFront가 Viewer 요청 단계에서 클라이언트 인증서를 검증하는 구조다.

```text
Client
  -> HTTPS + Client Certificate
  -> CloudFront Viewer mTLS
  -> ALB HTTPS
  -> App
```

필요 리소스와 설정은 다음과 같다.

| 항목 | 내용 | 담당/선행 |
| --- | --- | --- |
| Client CA bundle | 클라이언트 인증서를 서명한 CA 인증서 bundle | 임지혁 인증서 용도 정의 |
| CloudFront trust anchor/trust store | Viewer mTLS 검증에 사용할 신뢰 CA 구성 | 윤정우/임지혁 검토 |
| CloudFront Viewer mTLS 설정 | `app.finpay-sec.p-e.kr` viewer 요청에서 클라이언트 인증서 요구 | 윤정우 네트워크 검토 |
| 정상 클라이언트 인증서 | 허용되어야 하는 테스트 인증서 | 임지혁 |
| 비정상 인증서 | 인증서 없음, 잘못된 CA, 만료 인증서 | 임지혁 |
| 차단 테스트 | 정상/비정상 인증서 요청 결과 캡처 | 윤정우/김동규 |

적용 후 기대 흐름은 다음과 같다.

| 요청 조건 | 기대 결과 |
| --- | --- |
| 정상 클라이언트 인증서 있음 | CloudFront가 요청을 허용하고 ALB로 전달 |
| 클라이언트 인증서 없음 | CloudFront viewer 단계에서 차단 |
| 신뢰되지 않는 CA 인증서 | CloudFront viewer 단계에서 차단 |
| 만료 또는 잘못된 인증서 | CloudFront viewer 단계에서 차단 |

이 방식은 ALB Target Group, App 포트, App health check를 바꾸지 않아도 되므로 PoC 안정성이 높다.

현재 저장소에는 이 권장안을 구현하기 위한 Terraform 변수와 보조 스크립트가 추가되어 있다.

| 구현 항목 | 위치 | 설명 |
| --- | --- | --- |
| Viewer mTLS 활성화 변수 | `variables.tf`, `terraform.tfvars.example` | `enable_cloudfront_viewer_mtls`, `cloudfront_viewer_mtls_mode`, CA bundle 경로를 정의 |
| CA bundle 저장소 | `modules/app/main.tf` | CloudFront Trust Store가 참조할 전용 S3 버킷과 CA bundle object 생성 |
| Trust Store/배포 설정 | `scripts/cloudfront-viewer-mtls.sh` | CloudFront Trust Store 생성/갱신 후 배포의 `ViewerMtlsConfig` 적용 |
| 테스트 인증서 생성 | `scripts/generate-viewer-mtls-certs.sh` | 로컬 CA, 클라이언트 인증서, 브라우저 import용 P12 생성 |

Terraform AWS provider `5.100.0`에는 CloudFront `ViewerMtlsConfig` 블록이 아직 없어, CloudFront Trust Store와 배포 mTLS 설정은 AWS CLI 보조 스크립트로 반영한다. Terraform은 CloudFront 배포의 `etag`와 CA bundle object 변경을 감지해 보조 스크립트를 다시 실행한다.

적용 순서는 다음과 같다.

```bash
./scripts/generate-viewer-mtls-certs.sh
terraform init -reconfigure -backend-config=backend-dev.hcl
terraform apply
```

검증 명령은 다음과 같다.

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

`cloudfront_viewer_mtls_mode = "required"`일 때 인증서 없는 요청은 실패해야 하고, 생성된 정상 클라이언트 인증서를 붙인 요청은 성공해야 한다.

## 5. 대체안 구현 구상: Client -> ALB mTLS

대체안은 클라이언트가 ALB에 직접 접속하고, ALB가 trust store 기준으로 클라이언트 인증서를 검증하는 방식이다.

```text
Client
  -> HTTPS + Client Certificate
  -> ALB HTTPS Listener, mTLS verify
  -> Target Group
  -> App
```

이 방식은 ALB가 mTLS 기능을 직접 지원하므로 구현 예시가 명확하다. 단, 현재 운영 진입점은 CloudFront이므로 ALB 직접 mTLS는 운영 구조보다는 테스트 PoC에 더 적합하다.

Terraform 구현 예시는 다음과 같다.

```hcl
resource "aws_s3_bucket" "mtls_trust_store" {
  bucket = "${var.name_prefix}-mtls-trust-store"
}

resource "aws_s3_object" "client_ca_bundle" {
  bucket = aws_s3_bucket.mtls_trust_store.id
  key    = "ca/client-ca.pem"
  source = "certs/client-ca.pem"
}

resource "aws_lb_trust_store" "client_ca" {
  name                             = "${var.name_prefix}-client-ca-trust-store"
  ca_certificates_bundle_s3_bucket = aws_s3_bucket.mtls_trust_store.id
  ca_certificates_bundle_s3_key    = aws_s3_object.client_ca_bundle.key
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.alb_certificate_arn

  mutual_authentication {
    mode                             = "verify"
    trust_store_arn                  = aws_lb_trust_store.client_ca.arn
    ignore_client_certificate_expiry = false
  }

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app["payment"].arn
  }
}
```

ALB mTLS 대체안의 핵심 값은 다음과 같다.

| 값 | 의미 |
| --- | --- |
| `mode = "verify"` | ALB가 클라이언트 인증서를 trust store 기준으로 검증 |
| `trust_store_arn` | 검증에 사용할 ALB trust store ARN |
| `ignore_client_certificate_expiry = false` | 만료된 클라이언트 인증서를 허용하지 않음 |

## 6. 통신 경로 검토표

| 흐름 | 현재 경로 | 현재 프로토콜/포트 | 권장 PoC 후 기대 경로 | 검토 포인트 |
| --- | --- | --- | --- | --- |
| 사용자 요청 | Client -> CloudFront | HTTPS 443 | HTTPS 443 + Client Certificate | CloudFront가 인증서 검증 |
| Origin 요청 | CloudFront -> ALB | HTTPS 443 | 변경 없음 | 기존 `https-only` 유지 |
| App 전달 | ALB -> App Target Group | HTTP 8080 | 변경 없음 | 권장안은 앱 뒤쪽 구간을 바꾸지 않음 |
| Health Check | ALB -> App `/health` | HTTP 8080 | 변경 없음 | CloudFront mTLS는 ALB health check에 영향 없음 |
| DB 연결 | App -> RDS PostgreSQL | TCP 5432, `sslmode=require` | 변경 없음 | RDS TLS는 mTLS PoC 범위 밖 |

권장안은 CloudFront 앞단에서 클라이언트 인증서를 검증하므로 ALB -> App Target Group과 health check 설정을 바꾸지 않아도 된다.

## 7. SG/포트 변경 검토표

| 항목 | 현재 설정 | 권장 PoC 시 변경 후보 | 변경 필요 여부 | 의견 |
| --- | --- | --- | --- | --- |
| CloudFront Viewer | `app.finpay-sec.p-e.kr` alias, HTTPS redirect | Viewer mTLS 설정 추가 | 필요 | 권장안 핵심 변경 |
| ALB SG ingress | 80, 443 허용 또는 CloudFront origin-facing 제한 | 유지 | 없음 | ALB 직접 접근 제한 원칙 유지 |
| ALB HTTPS Listener | 443 HTTPS, ACM 인증서 | 유지 | 없음 | CloudFront mTLS는 ALB listener mTLS가 아님 |
| ALB SG egress | VPC CIDR 대상 TCP 8080 | 유지 | 없음 | ALB -> App 흐름은 그대로 유지 |
| App SG ingress | ALB SG에서 TCP 8080 허용 | 유지 | 없음 | 권장안은 App 포트를 바꾸지 않음 |
| Target Group | HTTP 8080 | 유지 | 없음 | health check 영향 최소화 |

네트워크 관점에서 권장안의 장점은 SG/포트 변경이 거의 없다는 점이다. 클라이언트 인증서 검증은 CloudFront viewer 구간에서 수행하고, 내부 origin 경로는 기존 HTTPS-only와 SG 접근제한 정책을 유지한다.

## 8. B안 장기 후보 검토: ALB -> App mTLS

B안은 `ALB -> App` 내부 구간을 mTLS 또는 HTTPS로 강화하는 방식이다.

```text
ALB
  -> HTTPS/mTLS
  -> App 또는 Nginx/Envoy
  -> Python App
```

보안 강화 효과는 크다. 현재 남아 있는 내부 HTTP 8080 구간을 줄일 수 있기 때문이다. 그러나 다음 문제가 있어 이번 단계의 실행 PoC에서는 제외한다.

| 이슈 | 설명 | 대안 |
| --- | --- | --- |
| Health Check | ALB health check가 클라이언트 인증서 없이 실패할 수 있음 | `/health`는 mTLS 제외, health 전용 포트, 프록시 처리 |
| App 영향 | Python 앱이 TLS/mTLS를 직접 처리해야 할 수 있음 | Nginx/Envoy sidecar 또는 프록시 사용 |
| 인증서 배포 | App 서버에 서버 인증서와 CA bundle 배포 필요 | Secrets Manager, SSM, AMI bake 방식 검토 |
| 포트 변경 | Target Group과 SG 포트 변경 필요 | 8080 유지 + 8443 병행 PoC 후 전환 |

B안 health check 대안은 다음 순서로 검토한다.

| 대안 | 내용 | 추천도 |
| --- | --- | --- |
| Health check는 mTLS 제외 | 업무 API만 mTLS 요구, `/health`는 ALB SG에서만 허용 | 높음 |
| Health check 전용 포트 | 업무 트래픽과 health check 포트 분리 | 중간 |
| ALB와 App 사이 프록시 | Nginx/Envoy가 TLS/mTLS와 health check 처리 | 중간~높음, 운영 복잡도 큼 |

## 9. 비정상 인증서 차단 검증 증적

권장안 PoC가 구성되면 아래 표로 증적을 캡처한다.

| 테스트 | 요청 조건 | 기대 결과 | 확인 위치 | 결과 |
| --- | --- | --- | --- | --- |
| 정상 인증서 | 신뢰 CA가 서명한 클라이언트 인증서 사용 | 요청 성공, `/health` 정상 | curl 결과, CloudFront 로그 |  |
| 인증서 없음 | 클라이언트 인증서 없이 요청 | CloudFront viewer 단계에서 차단 | curl 결과, CloudFront 로그 |  |
| 신뢰되지 않는 CA | 다른 CA가 서명한 인증서 사용 | 인증 실패 | curl 결과, CloudFront 로그 |  |
| 만료 인증서 | 만료된 클라이언트 인증서 사용 | 인증 실패 | curl 결과, CloudFront 로그 |  |
| 잘못된 인증서 용도 | ClientAuth 용도가 없거나 CN/SAN 정책 불일치 | 인증 실패 또는 정책상 거부 | curl 결과, CloudFront 로그 |  |

예시 검증 명령은 아래와 같다.

```bash
curl -v https://app.finpay-sec.p-e.kr/health

curl -v \
  --cert client.crt \
  --key client.key \
  https://app.finpay-sec.p-e.kr/health

curl -v \
  --cert wrong-client.crt \
  --key wrong-client.key \
  https://app.finpay-sec.p-e.kr/health

aws cloudfront get-distribution-config \
  --id "$CLOUDFRONT_DISTRIBUTION_ID"

aws elbv2 describe-target-health \
  --region ap-northeast-2 \
  --target-group-arn "$TARGET_GROUP_ARN"
```

## 10. 최종 mTLS 구조 검토 의견

| 관점 | 의견 |
| --- | --- |
| PoC 실행성 | `Client -> CloudFront Viewer mTLS`가 현재 운영 진입점과 가장 잘 맞는다. |
| 보안 강화성 | 외부 클라이언트 신원 검증은 CloudFront viewer 구간에서 수행하고, 내부 HTTP 8080 개선은 B안 장기 후보로 남긴다. |
| 현재 구조와의 관계 | CloudFront가 사용자 진입점이므로 ALB 직접 mTLS보다 CloudFront viewer mTLS가 더 자연스럽다. |
| 접근통제 | ALB 직접 접근 제한 원칙을 유지한다. CloudFront -> ALB는 기존 HTTPS-only와 SG 제한으로 보호한다. |
| Health Check | 권장안은 Target Group health check를 바꾸지 않아 안정적이다. B안은 health check 제외/전용 포트/프록시 대안이 필요하다. |
| 최종 판단 | 이번 단계에서는 `Client -> CloudFront Viewer mTLS`를 최종 권장 PoC로 선정하고, `Client -> ALB mTLS`는 대체 PoC, `ALB -> App mTLS`는 장기 내부망 Zero Trust 후보로 문서화한다. |

## 11. 제출 산출물 매핑

| 산출물 | 이 문서의 위치 |
| --- | --- |
| mTLS 적용 구간 정의서 | 3장 |
| 통신 경로 검토표 | 6장 |
| SG/포트 변경 검토표 | 7장 |
| 비정상 인증서 차단 검증 증적 | 9장 |
| 최종 mTLS 구조 검토 의견 | 10장 |
