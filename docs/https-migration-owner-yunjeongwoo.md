# HTTPS Migration Owner Plan

이 문서는 윤정우 담당 HTTPS 전환 산출물이다. 범위는 CloudFront, ALB, ACM, DNS이며, 기준일은 2026-06-02이다.

## 1. 담당 목표

CloudFront를 사용자 진입점으로 유지하면서 Viewer 구간과 CloudFront -> ALB Origin 구간을 모두 HTTPS로 전환한다. ALB는 443 Listener로 애플리케이션 트래픽을 forward하고, 80 Listener는 HTTPS redirect로 변경한다.

## 2. 선행 결정 사항

| 항목 | 결정 내용 |
| --- | --- |
| 사용할 커스텀 도메인 | `app.finpay-sec.p-e.kr` |
| CloudFront Origin 도메인 | `origin.finpay-sec.p-e.kr` |
| DNS 관리 방식 | Route 53 또는 외부 DNS 중 실제 보유 DNS에 맞춰 선택 |
| CloudFront 인증서 리전 | `us-east-1` |
| ALB 인증서 리전 | `ap-northeast-2` |
| 인증서 검증 방식 | DNS validation |
| CloudFront Origin Protocol | `https-only` |
| ALB 80 Listener | HTTPS Redirect |
| ALB 443 Listener | HTTPS Forward |
| Terraform 적용 방식 | `plan` 검토 후 `apply`, 증적 캡처, 필요 시 `destroy` |

## 3. 현재 구조와 개선 구조

| 구간 | 현재 구조 | 개선 구조 |
| --- | --- | --- |
| 사용자 -> CloudFront | CloudFront 기본 도메인 또는 alias, Viewer는 `redirect-to-https` | `app.finpay-sec.p-e.kr` alias와 `us-east-1` ACM 인증서를 Viewer Certificate로 사용 |
| CloudFront -> ALB | ALB DNS를 origin으로 사용 가능, 기본값은 `http-only` | `origin.finpay-sec.p-e.kr`을 origin으로 사용하고 `https-only` 적용 |
| 사용자 -> ALB 80 | HTTP 80 Listener가 target group으로 forward 가능 | HTTP 80 Listener는 HTTPS 443으로 `HTTP_301` redirect |
| 사용자/CloudFront -> ALB 443 | ACM ARN이 있을 때 조건부 생성 | `ap-northeast-2` ACM 인증서를 연결한 HTTPS Listener가 target group으로 forward |
| DNS | Terraform 변수 또는 외부 레코드에 의존 | Viewer alias, Origin alias, ACM DNS validation 레코드를 명시적으로 관리 |

## 4. 도메인 구조

| 도메인 | 용도 | 연결 대상 | 인증서 |
| --- | --- | --- | --- |
| `app.finpay-sec.p-e.kr` | 사용자 접속용 CloudFront Viewer 도메인 | CloudFront distribution domain | `us-east-1` ACM |
| `origin.finpay-sec.p-e.kr` | CloudFront가 ALB에 HTTPS로 접속할 때 쓰는 Origin 도메인 | ALB DNS name | `ap-northeast-2` ACM |

CloudFront Origin HTTPS는 TLS 인증서의 SAN과 Origin Domain Name이 일치해야 한다. 따라서 CloudFront origin을 ALB 기본 DNS 이름으로 두지 않고 `origin.finpay-sec.p-e.kr` 별칭을 ALB DNS로 연결한다.

## 5. Terraform 변경 계획

| 구분 | 항목 | 파일 또는 리소스 | 적용 내용 |
| --- | --- | --- | --- |
| 신규 또는 외부 준비 | CloudFront Viewer ACM | `us-east-1` ACM | `app.finpay-sec.p-e.kr` 인증서 발급, DNS validation 완료 |
| 신규 또는 외부 준비 | ALB Origin ACM | `ap-northeast-2` ACM | `origin.finpay-sec.p-e.kr` 인증서 발급, DNS validation 완료 |
| 신규 또는 외부 준비 | DNS validation CNAME | Route 53 또는 외부 DNS | ACM 검증 CNAME 등록 |
| 신규 또는 외부 준비 | Viewer DNS record | Route 53 또는 외부 DNS | `app.finpay-sec.p-e.kr` -> CloudFront distribution |
| 신규 또는 외부 준비 | Origin DNS record | Route 53 또는 외부 DNS | `origin.finpay-sec.p-e.kr` -> ALB DNS |
| 변경 | CloudFront aliases | `modules/app/main.tf` | `cloudfront_aliases`와 custom Viewer Certificate 사용 |
| 변경 | CloudFront Origin Protocol | `modules/app/main.tf` | `enable_cloudfront_origin_https=true`일 때 `https-only` |
| 변경 | ALB HTTP Listener | `modules/app/main.tf` | `enable_http_redirect=true`일 때 80 -> 443 redirect |
| 변경 | ALB HTTPS Listener | `modules/app/main.tf` | `enable_https_listener=true`와 ACM ARN으로 443 Listener 생성 |
| 변경 | Terraform outputs | `outputs.tf`, `modules/app/outputs.tf` | 증적 캡처용 CloudFront ID, Origin 도메인, Listener ARN 출력 |
| 삭제 가능 | 기존 HTTP forward rule | `aws_lb_listener_rule.http_*` | redirect 활성화 시 Terraform에서 조건부 제거 |

적용 변수 예시는 아래와 같다. 인증서 ARN은 DNS validation 완료 후 발급된 실제 ARN으로 교체한다.

```hcl
acm_certificate_arn = "arn:aws:acm:ap-northeast-2:<account-id>:certificate/<alb-origin-cert-id>"

enable_https_listener          = true
enable_http_redirect           = true
enable_cloudfront_origin_https = true

cloudfront_origin_domain_name  = "origin.finpay-sec.p-e.kr"
cloudfront_aliases             = ["app.finpay-sec.p-e.kr"]
cloudfront_acm_certificate_arn = "arn:aws:acm:us-east-1:<account-id>:certificate/<viewer-cert-id>"

app_base_url = "https://app.finpay-sec.p-e.kr"
```

## 6. 적용 순서

1. `app.finpay-sec.p-e.kr`용 ACM 인증서를 `us-east-1`에 요청한다.
2. `origin.finpay-sec.p-e.kr`용 ACM 인증서를 `ap-northeast-2`에 요청한다.
3. 두 인증서의 DNS validation CNAME을 DNS에 등록하고 `ISSUED` 상태를 확인한다.
4. `origin.finpay-sec.p-e.kr`을 ALB DNS로 연결한다.
5. Terraform 변수에 ACM ARN, CloudFront alias, origin 도메인, HTTPS 전환 플래그를 반영한다.
6. `terraform plan`에서 CloudFront 변경, ALB 443 추가, ALB 80 redirect 변경, HTTP listener rule 제거 범위를 확인한다.
7. 팀 합의 후 `terraform apply`를 실행한다.
8. CloudFront 배포 완료 후 HTTPS 접속과 ALB listener 상태를 캡처한다.

## 7. 증적 캡처 항목

| 증적 | 확인 명령 또는 화면 | 정상 기준 | 결과 |
| --- | --- | --- | --- |
| CloudFront domain | `terraform output cloudfront_distribution_domain_name` | CloudFront distribution domain 출력 |  |
| CloudFront ID | `terraform output cloudfront_distribution_id` | 배포 ID 출력 |  |
| CloudFront alias | `terraform output cloudfront_aliases` | `app.finpay-sec.p-e.kr` 포함 |  |
| CloudFront origin | `terraform output cloudfront_origin_domain_name` | `origin.finpay-sec.p-e.kr` 출력 |  |
| CloudFront origin policy | `aws cloudfront get-distribution-config --id "$CLOUDFRONT_ID"` | `OriginProtocolPolicy=https-only` |  |
| CloudFront viewer cert | CloudFront console 또는 CLI distribution config | ACM certificate ARN 사용, TLS policy `TLSv1.2_2021` |  |
| ALB 80 Listener | `aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN"` | 80 Listener default action이 `redirect` |  |
| ALB 443 Listener | `aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN"` | 443 Listener protocol `HTTPS`, ACM 인증서 연결 |  |
| ACM 상태 | `aws acm describe-certificate` | 두 인증서 모두 `ISSUED` |  |
| HTTPS 접속 결과 | `curl -I https://app.finpay-sec.p-e.kr/health` | HTTP 200 또는 앱 기준 정상 응답 |  |
| HTTP redirect 결과 | `curl -I http://app.finpay-sec.p-e.kr/health` | HTTPS로 301/302 redirect |  |

## 8. 점검 명령어

```bash
terraform output cloudfront_distribution_id
terraform output cloudfront_distribution_domain_name
terraform output cloudfront_aliases
terraform output cloudfront_origin_domain_name

ALB_ARN="$(aws elbv2 describe-load-balancers \
  --region ap-northeast-2 \
  --names finpay-dev-alb \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)"

aws elbv2 describe-listeners \
  --region ap-northeast-2 \
  --load-balancer-arn "$ALB_ARN" \
  --query 'Listeners[*].{Port:Port,Protocol:Protocol,Action:DefaultActions[0].Type,Cert:Certificates[0].CertificateArn}' \
  --output table

CLOUDFRONT_ID="$(terraform output -raw cloudfront_distribution_id)"

aws cloudfront get-distribution-config \
  --id "$CLOUDFRONT_ID" \
  --query 'DistributionConfig.{Aliases:Aliases.Items,Origins:Origins.Items[*].{DomainName:DomainName,OriginProtocolPolicy:CustomOriginConfig.OriginProtocolPolicy},ViewerCertificate:ViewerCertificate}'

aws acm list-certificates \
  --region us-east-1 \
  --query 'CertificateSummaryList[?DomainName==`app.finpay-sec.p-e.kr`]'

aws acm list-certificates \
  --region ap-northeast-2 \
  --query 'CertificateSummaryList[?DomainName==`origin.finpay-sec.p-e.kr`]'

curl -I https://app.finpay-sec.p-e.kr/health
curl -I http://app.finpay-sec.p-e.kr/health
```

## 9. 전송보안 개선표

| 개선 항목 | 전환 전 | 전환 후 | 보안 효과 |
| --- | --- | --- | --- |
| Viewer TLS | CloudFront 기본 인증서 또는 alias 미사용 | Custom domain과 `us-east-1` ACM 인증서 사용 | 사용자 접속 도메인 기준 TLS 신뢰성 확보 |
| CloudFront -> ALB | `http-only` 가능 | `https-only` | Edge 이후 Origin 구간 평문 HTTP 제거 |
| ALB HTTP 80 | target group forward 가능 | HTTPS redirect | ALB 직접 HTTP 접속의 평문 처리 제거 |
| ALB HTTPS 443 | 조건부 또는 미구성 | ACM 인증서 연결 후 forward | ALB origin 구간 TLS 종단 확보 |
| DNS/ACM 운영 | ARN 수동 주입 중심 | 검증 CNAME, Viewer alias, Origin alias를 증적으로 관리 | 인증서 발급과 도메인 소유 검증 추적 가능 |

## 10. 롤백 기준

CloudFront 배포 실패, 인증서 불일치, ALB 443 health 이상, Cognito callback 오류가 발생하면 `enable_cloudfront_origin_https=false`로 Origin HTTPS를 먼저 되돌린다. 필요하면 `enable_http_redirect=false`로 ALB 80 forward를 복구하고, 최종적으로 `cloudfront_aliases=[]`, `cloudfront_acm_certificate_arn=""`, `app_base_url=""` 순서로 사용자 접속 도메인 변경을 되돌린다.
