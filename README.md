# tectupSCPJ3 프로젝트 설명서 
kt tech up 사이버 보안 2기 기초 프로젝트 [3]


프로젝트명: 금융 규정 준수 핀테크 결제 인프라
- 팀명: 구름수호대
- 구성원: 김동규, 임지혁, 한경윤, 윤정우
- 사용 방법: terraform init → plan → apply

C:\project\tectupSCPJ3
│
├── README.md                          # 프로젝트 설명서
├── .gitignore                         # Git 제외 파일 목록
│
├── environments/                      # 환경별 설정
│   └── dev/
│       ├── main.tf                    # 모듈 호출, 프로바이더 설정
│       ├── variables.tf               # 변수 선언
│       ├── outputs.tf                 # 배포 결과 출력값 정의
│       ├── terraform.tfvars.example   # 변수 값 예시
│       └── backend.tf                 # 상태 파일 저장 위치
│
├── modules/                           # 재사용 가능한 인프라 모듈
│   ├── vpc/                           # VPC, 서브넷, IGW, NAT GW, 라우팅 테이블
│   ├── security-group/                # 보안 그룹 (ALB, App, DB)
│   ├── iam/                           # IAM 역할, 정책, Permission Set
│   ├── kms/                           # KMS 암호화 키
│   ├── s3/                            # S3 버킷, 암호화, Object Lock
│   ├── rds/                           # RDS PostgreSQL, Multi-AZ
│   ├── ec2/                           # EC2 Launch Template, Auto Scaling Group
│   ├── alb/                           # Application Load Balancer, Target Group
│   ├── cloudtrail/                    # CloudTrail 로그 수집
│   ├── cloudwatch/                    # CloudWatch 로그 그룹, 알람
│   └── lambda/                        # Lambda 함수 (Auto Remediation)
│
└── docs/                              # 프로젝트 문서
    ├── architecture.md                # 아키텍처 설계 문서
    ├── security-policy-matrix.md      # 역할별 접근 권한 표
    └── iam-role-specification.md      # IAM 정책 상세 명세