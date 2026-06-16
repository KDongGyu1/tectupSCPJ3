from __future__ import annotations

import html
import csv
import io
import json
import os
import re
import secrets
import socket
import ssl
import time
import uuid
import base64
from datetime import datetime, timedelta, timezone
from http import HTTPStatus
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlparse
from urllib.request import Request, urlopen
from column_crypto import encrypt_email, decrypt_email, hash_email


APP_PORT = int(os.environ.get("FINPAY_PORT", "8088"))
APP_TLS_ENABLED = os.environ.get("FINPAY_TLS_ENABLED", "false").strip().lower() == "true"
APP_TLS_CERT_FILE = os.environ.get("FINPAY_TLS_CERT_FILE", "")
APP_TLS_KEY_FILE = os.environ.get("FINPAY_TLS_KEY_FILE", "")
APP_ROOT = Path(__file__).resolve().parent
DATA_PATH = APP_ROOT / "data" / "finpay-data.json"

APP_CONFIG = {
    "environment": os.environ.get("FINPAY_ENV", "local"),
    "aws_region": os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION", "ap-northeast-2"),
    "storage": os.environ.get("FINPAY_STORAGE", "local"),
    "cognito_user_pool_id": os.environ.get("COGNITO_USER_POOL_ID", ""),
    "cognito_web_client_id": os.environ.get("COGNITO_WEB_CLIENT_ID", ""),
    "cognito_hosted_ui_url": os.environ.get("COGNITO_HOSTED_UI_URL", ""),
    "app_base_url": os.environ.get("APP_BASE_URL", ""),
    "database_url": os.environ.get("DATABASE_URL", ""),
    "rds_endpoint": os.environ.get("RDS_ENDPOINT", ""),
    "rds_master_secret_arn": os.environ.get("RDS_MASTER_SECRET_ARN", ""),
    "db_name": os.environ.get("DB_NAME", "finpay"),
    "db_user": os.environ.get("DB_USER", ""),
    "db_password": os.environ.get("DB_PASSWORD", ""),
    "rds_sslmode": os.environ.get("RDS_SSLMODE", "require"),
    "cloudwatch_log_group": os.environ.get("CLOUDWATCH_LOG_GROUP", ""),
    "cloudwatch_log_stream": os.environ.get("CLOUDWATCH_LOG_STREAM", ""),
}

STORAGE_WARNING = ""
CLOUDWATCH_SEQUENCE_TOKEN = None
CLOUDWATCH_READY = False
CLOUDWATCH_WARNING = ""

NAV_ITEMS = [
    ("대시보드", "/dashboard", {"Customer", "Merchant", "SettlementOperator", "Auditor", "OperationsAdmin"}),
    ("내 권한", "/my-access", {"Customer", "Merchant", "SettlementOperator", "Auditor", "OperationsAdmin"}),
    ("결제 생성", "/payments/new", {"Customer"}),
    ("결제 승인", "/payments/review", {"SettlementOperator"}),
    ("결제 내역", "/payments", {"Customer", "Merchant", "SettlementOperator", "Auditor", "OperationsAdmin"}),
    ("정산 조회", "/merchant/settlements", {"Merchant", "OperationsAdmin"}),
    ("감사 이벤트", "/audit/events", {"Auditor", "OperationsAdmin"}),
    ("가맹점 관리", "/operations/merchants", {"OperationsAdmin"}),
    ("보안 상태", "/security/status", {"OperationsAdmin"}),
    ("시스템 상태", "/system/status", {"OperationsAdmin"}),
]

ROLE_DESCRIPTIONS = {
    "Customer": "결제 요청을 생성하고 본인이 요청한 결제 내역을 조회합니다.",
    "Merchant": "가맹점에 접수된 결제 내역과 거래 상태를 조회합니다.",
    "SettlementOperator": "승인 대기 결제를 검토하고 승인 또는 거절합니다.",
    "Auditor": "결제 내역과 감사 이벤트를 조회합니다.",
    "OperationsAdmin": "결제 운영, 감사 조회, 시스템 상태를 관리합니다.",
}

ROLE_ALIASES = {
    "Admin": "OperationsAdmin",
    "Administrator": "OperationsAdmin",
}

ROLE_ALLOWED_APIS = {
    "Customer": ["GET /api/me", "GET /api/payments", "POST /payments"],
    "Merchant": ["GET /api/me", "GET /api/payments", "GET /merchant/settlements", "POST /payments/{id}/refund-request"],
    "SettlementOperator": ["GET /api/me", "GET /api/payments", "POST /payments/{id}/approve", "POST /payments/{id}/reject"],
    "Auditor": ["GET /api/me", "GET /api/payments", "GET /api/audit-events"],
    "OperationsAdmin": ["GET /api/me", "GET /api/payments", "GET /api/audit-events", "GET /api/config", "GET /api/db-check", "GET /operations/merchants", "POST /operations/merchants/assign", "POST /operations/merchants/unassign", "POST /payments/{id}/cancel", "POST /payments/{id}/refund", "POST /payments/{id}/refund-reject", "POST /payments/{id}/settle"],
}

PAYMENT_STATUSES = ["Pending", "Approved", "Rejected", "RefundRequested", "Refunded", "Cancelled", "Settled"]

STATUS_LABELS = {
    "Pending": "승인 대기",
    "Approved": "승인 완료",
    "Rejected": "거절",
    "RefundRequested": "환불 요청",
    "Refunded": "환불 완료",
    "Cancelled": "취소",
    "Settled": "정산 완료",
}

REGISTERED_MERCHANTS = [
    "FinPay Store",
    "FinPay Store2",
    "FinPay Store3",
]

DEFAULT_MERCHANT_EMAIL = "merchant@finpay.local"
DEFAULT_MERCHANT_ASSIGNMENTS = [
    {"email": DEFAULT_MERCHANT_EMAIL, "merchant": "FinPay Store"},
    {"email": DEFAULT_MERCHANT_EMAIL, "merchant": "FinPay Store3"},
]

SESSIONS: dict[str, dict] = {}
RECENT_DENIED_EVENTS: dict[tuple[str, str, str], float] = {}
KST = timezone(timedelta(hours=9), "KST")


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def esc(value: object) -> str:
    return html.escape(str(value), quote=True)


def default_merchant_assignments() -> list[dict]:
    return [dict(item) for item in DEFAULT_MERCHANT_ASSIGNMENTS]


def normalize_data(data: dict) -> dict:
    data.setdefault("payments", [])
    data.setdefault("audit_events", [])
    assignments = data.get("merchant_assignments")
    if assignments is None:
        assignments = default_merchant_assignments()
    normalized = []
    seen = set()
    for assignment in assignments:
        email = str(assignment.get("email", "")).strip().lower()
        merchant = str(assignment.get("merchant", "")).strip()
        key = (email, merchant)
        if email and merchant in REGISTERED_MERCHANTS and key not in seen:
            normalized.append({"email": email, "merchant": merchant})
            seen.add(key)
    data["merchant_assignments"] = normalized
    return data


def seed_data() -> dict:
    return {
        "payments": [
            {
                "id": "PAY-1001",
                "merchant": "FinPay Store",
                "amount": 120000,
                "status": "Pending",
                "created_by": "customer@finpay.local",
                "created_at": now_iso(),
                "memo": "초기 결제 요청",
            }
        ],
        "audit_events": [
            {
                "id": "EVT-1",
                "time": now_iso(),
                "actor": "system",
                "role": "System",
                "action": "APP_BOOTSTRAP",
                "result": "Success",
                "detail": "로컬 Python 앱 데이터 초기화",
            }
        ],
        "merchant_assignments": default_merchant_assignments(),
    }


def load_data() -> dict:
    if APP_CONFIG["storage"] == "postgres":
        try:
            return postgres_load_data()
        except Exception as exc:
            set_storage_warning(f"PostgreSQL load failed: {exc}")

    if not DATA_PATH.exists():
        DATA_PATH.parent.mkdir(parents=True, exist_ok=True)
        seed = normalize_data(seed_data())
        save_data(seed)
        return seed

    with DATA_PATH.open("r", encoding="utf-8") as fp:
        return normalize_data(json.load(fp))


def save_data(data: dict) -> None:
    data = normalize_data(data)
    if APP_CONFIG["storage"] == "postgres":
        try:
            postgres_save_data(data)
            return
        except Exception as exc:
            set_storage_warning(f"PostgreSQL save failed: {exc}")

    DATA_PATH.parent.mkdir(parents=True, exist_ok=True)
    with DATA_PATH.open("w", encoding="utf-8") as fp:
        json.dump(data, fp, ensure_ascii=False, indent=2)


def add_event(actor: str, role: str, action: str, result: str, detail: str) -> None:
    if APP_CONFIG["storage"] == "postgres":
        try:
            event = postgres_add_event(actor, role, action, result, detail)
            emit_structured_log(event)
            return
        except Exception as exc:
            set_storage_warning(f"PostgreSQL audit insert failed: {exc}")

    data = load_data()
    event_id = f"EVT-{len(data['audit_events']) + 1}"
    event = {
        "id": event_id,
        "time": now_iso(),
        "actor": actor,
        "role": role,
        "action": action,
        "result": result,
        "detail": detail,
    }
    data["audit_events"].insert(0, event)
    save_data(data)
    emit_structured_log(event)


def set_storage_warning(message: str) -> None:
    global STORAGE_WARNING
    STORAGE_WARNING = message


def add_denied_event_once(actor: str, role: str, action: str, detail: str, window_seconds: int = 2) -> None:
    key = (actor, role, action)
    current = time.time()
    previous = RECENT_DENIED_EVENTS.get(key, 0)
    if current - previous < window_seconds:
        return
    RECENT_DENIED_EVENTS[key] = current
    add_event(actor, role, action, "Denied", detail)


def set_cloudwatch_warning(message: str) -> None:
    global CLOUDWATCH_WARNING
    CLOUDWATCH_WARNING = message


def import_psycopg():
    try:
        import psycopg  # type: ignore

        return psycopg
    except ImportError as exc:
        raise RuntimeError("psycopg is not installed. Run: python -m pip install -r app/requirements.txt") from exc


def secret_db_config() -> dict:
    if not APP_CONFIG["rds_master_secret_arn"]:
        return {}
    try:
        import boto3  # type: ignore
    except ImportError:
        return {}

    client = boto3.client("secretsmanager", region_name=APP_CONFIG["aws_region"])
    response = client.get_secret_value(SecretId=APP_CONFIG["rds_master_secret_arn"])
    secret = response.get("SecretString", "{}")
    return json.loads(secret)


def cloudwatch_client():
    if not APP_CONFIG["cloudwatch_log_group"]:
        return None
    try:
        import boto3  # type: ignore
    except ImportError:
        set_cloudwatch_warning("boto3 is not installed. Run: python -m pip install -r app/requirements.txt")
        return None
    return boto3.client("logs", region_name=APP_CONFIG["aws_region"])


def ensure_cloudwatch_stream(client) -> bool:
    global CLOUDWATCH_READY, CLOUDWATCH_SEQUENCE_TOKEN
    if CLOUDWATCH_READY:
        return True

    log_group = APP_CONFIG["cloudwatch_log_group"]
    log_stream = APP_CONFIG["cloudwatch_log_stream"]
    if not log_stream:
        log_stream = f"{socket.gethostname()}-{APP_PORT}"
        APP_CONFIG["cloudwatch_log_stream"] = log_stream

    try:
        client.create_log_stream(logGroupName=log_group, logStreamName=log_stream)
    except client.exceptions.ResourceAlreadyExistsException:
        pass
    except client.exceptions.ResourceNotFoundException:
        set_cloudwatch_warning(f"CloudWatch log group does not exist: {log_group}")
        return False
    except Exception as exc:
        set_cloudwatch_warning(f"CloudWatch log stream setup failed: {exc}")
        return False

    try:
        response = client.describe_log_streams(
            logGroupName=log_group,
            logStreamNamePrefix=log_stream,
            limit=1,
        )
        streams = response.get("logStreams", [])
        if streams:
            CLOUDWATCH_SEQUENCE_TOKEN = streams[0].get("uploadSequenceToken")
    except Exception as exc:
        set_cloudwatch_warning(f"CloudWatch log stream lookup failed: {exc}")
        return False

    CLOUDWATCH_READY = True
    set_cloudwatch_warning("")
    return True


def emit_structured_log(event: dict) -> None:
    global CLOUDWATCH_SEQUENCE_TOKEN, CLOUDWATCH_READY
    client = cloudwatch_client()
    if client is None or not ensure_cloudwatch_stream(client):
        return

    payload = {
        "application": "finpay-python-app",
        "environment": APP_CONFIG["environment"],
        "storage": APP_CONFIG["storage"],
        "event": event,
    }
    entry = {
        "timestamp": int(time.time() * 1000),
        "message": json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
    }
    request = {
        "logGroupName": APP_CONFIG["cloudwatch_log_group"],
        "logStreamName": APP_CONFIG["cloudwatch_log_stream"],
        "logEvents": [entry],
    }
    if CLOUDWATCH_SEQUENCE_TOKEN:
        request["sequenceToken"] = CLOUDWATCH_SEQUENCE_TOKEN

    try:
        response = client.put_log_events(**request)
        CLOUDWATCH_SEQUENCE_TOKEN = response.get("nextSequenceToken")
        set_cloudwatch_warning("")
    except client.exceptions.InvalidSequenceTokenException:
        CLOUDWATCH_READY = False
        if ensure_cloudwatch_stream(client):
            request.pop("sequenceToken", None)
            if CLOUDWATCH_SEQUENCE_TOKEN:
                request["sequenceToken"] = CLOUDWATCH_SEQUENCE_TOKEN
            response = client.put_log_events(**request)
            CLOUDWATCH_SEQUENCE_TOKEN = response.get("nextSequenceToken")
            set_cloudwatch_warning("")
    except Exception as exc:
        set_cloudwatch_warning(f"CloudWatch log delivery failed: {exc}")


def postgres_conninfo() -> str:
    if APP_CONFIG["database_url"]:
        return APP_CONFIG["database_url"]

    secret = secret_db_config()
    host = secret.get("host") or APP_CONFIG["rds_endpoint"]
    port = int(secret.get("port") or 5432)
    dbname = secret.get("dbname") or secret.get("dbInstanceIdentifier") or APP_CONFIG["db_name"]
    user = secret.get("username") or APP_CONFIG["db_user"]
    password = secret.get("password") or APP_CONFIG["db_password"]

    if not host or not user or not password:
        raise RuntimeError("PostgreSQL credentials are incomplete. Set DATABASE_URL or DB_USER/DB_PASSWORD/RDS_ENDPOINT.")

    sslmode = APP_CONFIG["rds_sslmode"].strip()
    conninfo = f"host={host} port={port} dbname={dbname} user={user} password={password} connect_timeout=3"
    if sslmode:
        conninfo = f"{conninfo} sslmode={sslmode}"
    return conninfo


def postgres_connect():
    psycopg = import_psycopg()
    return psycopg.connect(postgres_conninfo())


def ensure_postgres_schema() -> None:
    with postgres_connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                create table if not exists payments (
                  id text primary key,
                  merchant text not null,
                  amount integer not null,
                  status text not null,
                  created_by text not null,
                  created_at text not null,
                  memo text,
                  reviewed_by text,
                  reviewed_at text
                )
                """
            )
            cur.execute(
                """
                create table if not exists audit_events (
                  id text primary key,
                  time text not null,
                  actor text not null,
                  role text not null,
                  action text not null,
                  result text not null,
                  detail text not null
                )
                """
            )

            cur.execute(
                """
                create table if not exists merchant_assignments (
                  email_hash text not null,
                  email_enc text not null,
                  merchant text not null,
                  primary key (email_hash, merchant)
                )
                """
            )

            cur.execute(
                """
                alter table merchant_assignments
                add column if not exists email_hash text
                """
            )

            cur.execute(
                """
                alter table merchant_assignments
                add column if not exists email_enc text
                """
            )

            cur.execute(
                """
                select column_name
                from information_schema.columns
                where table_schema = 'public'
                  and table_name = 'merchant_assignments'
                  and column_name = 'email'
                """
            )
            has_plain_email_column = cur.fetchone() is not None

            if has_plain_email_column:
                cur.execute(
                    """
                    select email, merchant
                    from merchant_assignments
                    where email is not null
                    """
                )

                rows = cur.fetchall()

                for email, merchant in rows:
                    cur.execute(
                        """
                        update merchant_assignments
                        set email_hash = %s,
                            email_enc = %s
                        where email = %s
                          and merchant = %s
                        """,
                        (hash_email(email), encrypt_email(email), email, merchant),
                    )

                cur.execute(
                    """
                    alter table merchant_assignments
                    drop constraint if exists merchant_assignments_pkey
                    """
                )

                cur.execute(
                    """
                    alter table merchant_assignments
                    alter column email_hash set not null
                    """
                )

                cur.execute(
                    """
                    alter table merchant_assignments
                    alter column email_enc set not null
                    """
                )

                cur.execute(
                    """
                    alter table merchant_assignments
                    add constraint merchant_assignments_pkey
                    primary key (email_hash, merchant)
                    """
                )

                cur.execute(
                    """
                    alter table merchant_assignments
                    drop column if exists email
                    """
                )


def postgres_load_data() -> dict:
    ensure_postgres_schema()
    with postgres_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("select id, merchant, amount, status, created_by, created_at, memo, reviewed_by, reviewed_at from payments order by created_at desc")
            payments = [
                {
                    "id": row[0],
                    "merchant": row[1],
                    "amount": row[2],
                    "status": row[3],
                    "created_by": row[4],
                    "created_at": row[5],
                    "memo": row[6] or "",
                    "reviewed_by": row[7] or "",
                    "reviewed_at": row[8] or "",
                }
                for row in cur.fetchall()
            ]
            cur.execute("select id, time, actor, role, action, result, detail from audit_events order by time desc")
            audit_events = [
                {
                    "id": row[0],
                    "time": row[1],
                    "actor": row[2],
                    "role": row[3],
                    "action": row[4],
                    "result": row[5],
                    "detail": row[6],
                }
                for row in cur.fetchall()
            ]
            cur.execute(
                """
                select email_enc, merchant
                from merchant_assignments
                order by merchant, email_hash
                """
            )
            merchant_assignments = [
                {
                    "email": decrypt_email(row[0]),
                    "merchant": row[1],
                }
                for row in cur.fetchall()
            ]

    if not payments and not audit_events:
        seed = normalize_data(seed_data())
        postgres_save_data(seed)
        return seed
    should_seed_assignments = not merchant_assignments
    if should_seed_assignments:
        merchant_assignments = default_merchant_assignments()
    data = normalize_data({"payments": payments, "audit_events": audit_events, "merchant_assignments": merchant_assignments})
    if should_seed_assignments:
        postgres_save_data(data)
    return data


def postgres_save_data(data: dict) -> None:
    ensure_postgres_schema()
    data = normalize_data(data)
    with postgres_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("delete from payments")
            for payment in data["payments"]:
                cur.execute(
                    """
                    insert into payments (id, merchant, amount, status, created_by, created_at, memo, reviewed_by, reviewed_at)
                    values (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        payment["id"],
                        payment["merchant"],
                        payment["amount"],
                        payment["status"],
                        payment["created_by"],
                        payment["created_at"],
                        payment.get("memo", ""),
                        payment.get("reviewed_by", ""),
                        payment.get("reviewed_at", ""),
                    ),
                )
            cur.execute("delete from audit_events")
            for event in data["audit_events"]:
                cur.execute(
                    """
                    insert into audit_events (id, time, actor, role, action, result, detail)
                    values (%s, %s, %s, %s, %s, %s, %s)
                    """,
                    (event["id"], event["time"], event["actor"], event["role"], event["action"], event["result"], event["detail"]),
                )
            cur.execute("delete from merchant_assignments")

            for assignment in data["merchant_assignments"]:
                email = assignment["email"]
                merchant = assignment["merchant"]

                cur.execute(
                    """
                    insert into merchant_assignments (email_hash, email_enc, merchant)
                    values (%s, %s, %s)
                    on conflict (email_hash, merchant) do update
                    set email_enc = excluded.email_enc
                    """,
                    (hash_email(email), encrypt_email(email), merchant),
                )

def postgres_add_event(actor: str, role: str, action: str, result: str, detail: str) -> dict:
    ensure_postgres_schema()
    with postgres_connect() as conn:
        with conn.cursor() as cur:
            cur.execute("select count(*) from audit_events")
            count = cur.fetchone()[0]
            event = {
                "id": f"EVT-{count + 1}",
                "time": now_iso(),
                "actor": actor,
                "role": role,
                "action": action,
                "result": result,
                "detail": detail,
            }
            cur.execute(
                """
                insert into audit_events (id, time, actor, role, action, result, detail)
                values (%s, %s, %s, %s, %s, %s, %s)
                """,
                (event["id"], event["time"], actor, role, action, result, detail),
            )
            return event


def format_money(amount: int) -> str:
    return f"{amount:,} KRW"


def format_datetime(value: object) -> str:
    text = str(value or "").strip()
    if not text or text == "-":
        return "-"
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(KST).strftime("%Y-%m-%d %H:%M:%S KST")
    except ValueError:
        return text


def approved_amount(payments: list[dict]) -> int:
    return sum(p["amount"] for p in payments if p["status"] == "Approved")


def settlement_amount(payments: list[dict]) -> int:
    return sum(p["amount"] for p in payments if p["status"] == "Settled")


def status_label(status: str) -> str:
    return STATUS_LABELS.get(status, status)


def normalize_role(role: str) -> str:
    return ROLE_ALIASES.get(role, role)


def actor_label(viewer: dict, email: str) -> str:
    if not email or email == "-":
        return "-"
    if email == viewer["email"]:
        return "본인"
    if viewer["role"] in {"Customer", "Merchant"}:
        return "FinPay 운영팀" if email == "ops@finpay.local" else mask_value(email)
    return email


def merchant_assignment_map(data: dict) -> dict[str, set[str]]:
    assignments: dict[str, set[str]] = {}
    for assignment in normalize_data(data).get("merchant_assignments", []):
        assignments.setdefault(assignment["email"], set()).add(assignment["merchant"])
    return assignments


def assigned_merchants(user: dict, data: dict | None = None) -> set[str]:
    if user["role"] == "Merchant":
        source = data if data is not None else load_data()
        return merchant_assignment_map(source).get(user["email"].lower(), set())
    return set(REGISTERED_MERCHANTS)


def visible_payments(data: dict, user: dict) -> list[dict]:
    if user["role"] == "Customer":
        return [p for p in data["payments"] if p["created_by"] == user["email"]]
    if user["role"] == "Merchant":
        merchant_names = assigned_merchants(user, data)
        return [p for p in data["payments"] if p["merchant"] in merchant_names]
    if user["role"] in {"SettlementOperator", "Auditor", "OperationsAdmin"}:
        return list(data["payments"])
    return []


def visible_audit_events(data: dict, user: dict) -> list[dict]:
    if user["role"] in {"Auditor", "OperationsAdmin"}:
        return list(data["audit_events"])
    payments = visible_payments(data, user)
    visible_ids = {p["id"] for p in payments}
    return [
        event for event in data["audit_events"]
        if event["actor"] == user["email"] or any(payment_id in event["detail"] for payment_id in visible_ids)
    ]


def find_visible_payment(data: dict, user: dict, payment_id: str) -> dict | None:
    for payment in visible_payments(data, user):
        if payment["id"] == payment_id:
            return payment
    return None


def filter_payments(payments: list[dict], status: str, keyword: str) -> list[dict]:
    filtered = payments
    if status != "All":
        filtered = [p for p in filtered if p["status"] == status]
    if keyword:
        needle = keyword.lower()
        filtered = [
            p for p in filtered
            if needle in p["id"].lower()
            or needle in p["merchant"].lower()
            or needle in p["created_by"].lower()
            or needle in p.get("memo", "").lower()
        ]
    return filtered


def count_by_status(payments: list[dict]) -> dict[str, int]:
    return {status: sum(1 for p in payments if p["status"] == status) for status in PAYMENT_STATUSES}


def count_by_result(events: list[dict]) -> dict[str, int]:
    return {
        "Success": sum(1 for e in events if e["result"] == "Success"),
        "Denied": sum(1 for e in events if e["result"] == "Denied"),
    }


def mask_value(value: str) -> str:
    if not value:
        return ""
    if len(value) <= 12:
        return value
    return f"{value[:6]}...{value[-6:]}"


def public_base_url(headers) -> str:
    if APP_CONFIG["app_base_url"]:
        return APP_CONFIG["app_base_url"].rstrip("/")
    host = headers.get("Host", f"127.0.0.1:{APP_PORT}")
    proto = headers.get("X-Forwarded-Proto", "http")
    return f"{proto}://{host}".rstrip("/")


def is_secure_request(headers) -> bool:
    forwarded_proto = headers.get("X-Forwarded-Proto", "").lower()
    if forwarded_proto == "https":
        return True
    return public_base_url(headers).lower().startswith("https://")


def cognito_redirect_uri(headers) -> str:
    return f"{public_base_url(headers)}/auth/callback"


def cognito_login_url(headers) -> str:
    query = urlencode(
        {
            "client_id": APP_CONFIG["cognito_web_client_id"],
            "response_type": "code",
            "scope": "openid email profile",
            "redirect_uri": cognito_redirect_uri(headers),
        }
    )
    return f"{APP_CONFIG['cognito_hosted_ui_url'].rstrip('/')}/oauth2/authorize?{query}"


def cognito_logout_url(headers) -> str:
    query = urlencode(
        {
            "client_id": APP_CONFIG["cognito_web_client_id"],
            "logout_uri": f"{public_base_url(headers)}/login",
        }
    )
    return f"{APP_CONFIG['cognito_hosted_ui_url'].rstrip('/')}/logout?{query}"


def decode_jwt_payload(token: str) -> dict:
    try:
        payload = token.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        return json.loads(base64.urlsafe_b64decode(payload.encode("utf-8")))
    except Exception:
        return {}


def exchange_cognito_code(code: str, headers) -> dict:
    token_url = f"{APP_CONFIG['cognito_hosted_ui_url'].rstrip('/')}/oauth2/token"
    body = urlencode(
        {
            "grant_type": "authorization_code",
            "client_id": APP_CONFIG["cognito_web_client_id"],
            "code": code,
            "redirect_uri": cognito_redirect_uri(headers),
        }
    ).encode("utf-8")
    request = Request(
        token_url,
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    with urlopen(request, timeout=5) as response:
        return json.loads(response.read().decode("utf-8"))


def cognito_user_from_tokens(tokens: dict) -> dict:
    id_payload = decode_jwt_payload(tokens.get("id_token", ""))
    email = id_payload.get("email") or id_payload.get("cognito:username") or "cognito-user"
    groups = id_payload.get("cognito:groups") or []
    if isinstance(groups, str):
        groups = [groups]
    role = next((normalize_role(group) for group in groups if normalize_role(group) in ROLE_DESCRIPTIONS), "")
    if not role:
        raise ValueError("Cognito group is not mapped to an application role.")
    return {
        "email": email,
        "name": id_payload.get("name") or email.split("@")[0],
        "role": role,
        "auth_provider": "cognito",
    }


def integration_status() -> dict:
    return {
        "environment": APP_CONFIG["environment"],
        "aws_region": APP_CONFIG["aws_region"],
        "storage": {
            "mode": APP_CONFIG["storage"],
            "warning": STORAGE_WARNING,
        },
        "cognito": {
            "configured": bool(APP_CONFIG["cognito_user_pool_id"] and APP_CONFIG["cognito_web_client_id"]),
            "hosted_ui_configured": bool(APP_CONFIG["cognito_hosted_ui_url"]),
            "user_pool_id": APP_CONFIG["cognito_user_pool_id"],
            "web_client_id": APP_CONFIG["cognito_web_client_id"],
            "hosted_ui_url": APP_CONFIG["cognito_hosted_ui_url"],
        },
        "rds": db_probe(),
        "secrets_manager": {
            "configured": bool(APP_CONFIG["rds_master_secret_arn"]),
            "secret_arn": mask_value(APP_CONFIG["rds_master_secret_arn"]),
        },
        "cloudwatch": {
            "configured": bool(APP_CONFIG["cloudwatch_log_group"]),
            "log_group": APP_CONFIG["cloudwatch_log_group"],
            "log_stream": APP_CONFIG["cloudwatch_log_stream"],
            "warning": CLOUDWATCH_WARNING,
        },
    }


def db_probe() -> dict:
    endpoint = APP_CONFIG["rds_endpoint"]
    if not endpoint:
        return {
            "configured": False,
            "status": "local-storage",
            "detail": "RDS_ENDPOINT is not configured",
        }

    started = time.time()
    try:
        with socket.create_connection((endpoint, 5432), timeout=3):
            latency_ms = int((time.time() - started) * 1000)
            return {
                "configured": True,
                "status": "reachable",
                "host": endpoint,
                "port": 5432,
                "latency_ms": latency_ms,
            }
    except OSError as exc:
        return {
            "configured": True,
            "status": "unreachable",
            "host": endpoint,
            "port": 5432,
            "error": str(exc),
        }


def to_csv(rows: list[dict], fields: list[str]) -> str:
    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=fields, extrasaction="ignore")
    writer.writeheader()
    writer.writerows(rows)
    return output.getvalue()


def allowed_nav_items(user: dict) -> list[tuple[str, str]]:
    return [
        (label, path)
        for label, path, roles in NAV_ITEMS
        if user["role"] in roles
    ]


class FinPayHandler(BaseHTTPRequestHandler):
    server_version = "FinPay"

    def version_string(self) -> str:
        return self.server_version

    def do_HEAD(self) -> None:
        path = urlparse(self.path).path
        if path in ("/health", "/api/health"):
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_security_headers()
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if path == "/login":
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_security_headers()
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        self.send_response(HTTPStatus.METHOD_NOT_ALLOWED)
        self.send_header("Allow", "GET, POST, HEAD")
        self.send_security_headers()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path

        if path in ("/health", "/api/health"):
            self.send_json({"status": "healthy", "service": "finpay", "environment": APP_CONFIG["environment"]})
            return

        if path == "/api/db-check":
            user = self.require_login()
            if not user:
                return
            if user["role"] not in {"OperationsAdmin"}:
                add_event(user["email"], user["role"], "GET_DB_CHECK_API", "Denied", "데이터베이스 상태 API 접근 권한 없음")
                self.send_json({"error": "forbidden"}, HTTPStatus.FORBIDDEN)
                return
            data = load_data()
            probe = db_probe()
            self.send_json(
                {
                    "status": probe["status"],
                    "storage": APP_CONFIG["storage"],
                    "rds": probe,
                    "payments": len(data["payments"]),
                    "audit_events": len(data["audit_events"]),
                }
            )
            return

        if path == "/api/config":
            user = self.require_login()
            if not user:
                return
            if user["role"] not in {"OperationsAdmin"}:
                add_event(user["email"], user["role"], "GET_CONFIG_API", "Denied", "연동 설정 API 접근 권한 없음")
                self.send_json({"error": "forbidden"}, HTTPStatus.FORBIDDEN)
                return
            self.send_json(integration_status())
            return

        if path == "/api/payments":
            user = self.require_login()
            if not user:
                return
            payments = visible_payments(load_data(), user)
            self.send_json({"payments": payments, "count": len(payments)})
            return

        if path == "/api/me":
            user = self.require_login()
            if not user:
                return
            self.send_json(
                {
                    "email": user["email"],
                    "name": user["name"],
                    "role": user["role"],
                    "description": ROLE_DESCRIPTIONS[user["role"]],
                    "allowed_routes": [{"label": label, "path": route} for label, route in allowed_nav_items(user)],
                }
            )
            return

        if path == "/api/audit-events":
            user = self.require_login()
            if not user:
                return
            if user["role"] not in {"Auditor", "OperationsAdmin"}:
                add_event(user["email"], user["role"], "GET_AUDIT_EVENTS_API", "Denied", "감사 이벤트 API 접근 권한 없음")
                self.send_json({"error": "forbidden"}, HTTPStatus.FORBIDDEN)
                return
            events = load_data()["audit_events"]
            self.send_json({"events": events[:100], "count": len(events)})
            return

        if path in ("", "/"):
            self.redirect("/dashboard" if self.current_user() else "/login")
            return

        if path == "/login":
            self.send_html(self.login_page())
            return

        if path == "/auth/cognito/start":
            if not APP_CONFIG["cognito_hosted_ui_url"]:
                self.send_html(self.login_page("로그인 서비스가 아직 준비되지 않았습니다."), HTTPStatus.BAD_REQUEST)
                return
            self.redirect(cognito_login_url(self.headers))
            return

        if path == "/auth/callback":
            code = parse_qs(parsed.query).get("code", [""])[0]
            if not code:
                self.send_html(self.login_page("로그인 요청 정보를 확인할 수 없습니다."), HTTPStatus.BAD_REQUEST)
                return
            try:
                tokens = exchange_cognito_code(code, self.headers)
                user = cognito_user_from_tokens(tokens)
            except Exception as exc:
                self.send_html(self.login_page("로그인 처리 중 문제가 발생했습니다. 관리자에게 문의해 주세요."), HTTPStatus.BAD_REQUEST)
                return
            sid = uuid.uuid4().hex
            user["csrf_token"] = secrets.token_urlsafe(32)
            SESSIONS[sid] = user
            role = user["role"]
            add_event(user["email"], user["role"], "LOGIN", "Success", "서비스 로그인")
            self.send_response(HTTPStatus.SEE_OTHER)
            self.send_header("Location", "/dashboard")
            self.send_header("Set-Cookie", self.session_cookie_header(sid))
            self.send_security_headers()
            self.end_headers()
            return

        user = self.require_login()
        if not user:
            return

        if path == "/export/payments.csv":
            if user["role"] not in {"Customer", "Merchant", "SettlementOperator", "Auditor", "OperationsAdmin"}:
                add_event(user["email"], user["role"], "EXPORT_PAYMENTS", "Denied", "결제 내보내기 권한 없음")
                self.send_html(self.forbidden_page(user, {"Customer", "Merchant", "SettlementOperator", "Auditor", "OperationsAdmin"}), HTTPStatus.FORBIDDEN)
                return
            rows = visible_payments(load_data(), user)
            add_event(user["email"], user["role"], "EXPORT_PAYMENTS", "Success", "결제 CSV 내보내기")
            self.send_csv("finpay-payments.csv", to_csv(rows, ["id", "status", "merchant", "amount", "created_by", "created_at", "reviewed_by", "reviewed_at", "memo"]))
            return

        if path == "/export/audit-events.csv":
            if user["role"] not in {"Auditor", "OperationsAdmin"}:
                add_event(user["email"], user["role"], "EXPORT_AUDIT_EVENTS", "Denied", "감사 이벤트 내보내기 권한 없음")
                self.send_html(self.forbidden_page(user, {"Auditor", "OperationsAdmin"}), HTTPStatus.FORBIDDEN)
                return
            rows = load_data()["audit_events"]
            add_event(user["email"], user["role"], "EXPORT_AUDIT_EVENTS", "Success", "감사 이벤트 CSV 내보내기")
            self.send_csv("finpay-audit-events.csv", to_csv(rows, ["id", "time", "actor", "role", "action", "result", "detail"]))
            return

        routes = {
            "/dashboard": (self.dashboard_page, {"Customer", "Merchant", "SettlementOperator", "Auditor", "OperationsAdmin"}),
            "/my-access": (self.my_access_page, {"Customer", "Merchant", "SettlementOperator", "Auditor", "OperationsAdmin"}),
            "/payments/new": (self.new_payment_page, {"Customer"}),
            "/payments/review": (self.review_payments_page, {"SettlementOperator"}),
            "/payments": (self.payment_history_page, {"Customer", "Merchant", "SettlementOperator", "Auditor", "OperationsAdmin"}),
            "/detail": (self.payment_detail_from_query_page, {"Customer", "Merchant", "SettlementOperator", "Auditor", "OperationsAdmin"}),
            "/merchant/settlements": (self.merchant_settlements_page, {"Merchant", "OperationsAdmin"}),
            "/audit/events": (self.audit_events_page, {"Auditor", "OperationsAdmin"}),
            "/operations/merchants": (self.merchant_admin_page, {"OperationsAdmin"}),
            "/security/status": (self.security_status_page, {"OperationsAdmin"}),
            "/system/status": (self.system_status_page, {"OperationsAdmin"}),
        }

        if path not in routes:
            self.send_error_page(HTTPStatus.NOT_FOUND, "페이지를 찾을 수 없습니다.")
            return

        page, allowed_roles = routes[path]
        if user["role"] not in allowed_roles:
            add_denied_event_once(user["email"], user["role"], f"GET {path}", "권한 없는 화면 접근")
            self.send_html(self.forbidden_page(user, allowed_roles), HTTPStatus.FORBIDDEN)
            return

        self.send_html(page(user))

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        form = self.read_form()

        if path == "/auth/logout":
            user = self.current_user()
            if user and not self.valid_csrf_token(form):
                self.reject_csrf(user)
                return
            if user:
                add_event(user["email"], user["role"], "LOGOUT", "Success", "로그아웃")
            self.send_response(HTTPStatus.SEE_OTHER)
            self.send_header(
                "Location",
                cognito_logout_url(self.headers) if user and user.get("auth_provider") == "cognito" and APP_CONFIG["cognito_hosted_ui_url"] else "/login",
            )
            self.send_header("Set-Cookie", self.session_cookie_header("", max_age=0))
            self.send_security_headers()
            self.end_headers()
            return

        user = self.require_login()
        if not user:
            return
        if not self.valid_csrf_token(form):
            self.reject_csrf(user)
            return

        if path == "/payments":
            self.create_payment(user, form)
            return

        if path == "/operations/merchants/assign":
            self.assign_merchant(user, form)
            return

        if path == "/operations/merchants/unassign":
            self.unassign_merchant(user, form)
            return

        approve_match = re.fullmatch(r"/payments/([^/]+)/approve", path)
        reject_match = re.fullmatch(r"/payments/([^/]+)/reject", path)
        cancel_match = re.fullmatch(r"/payments/([^/]+)/cancel", path)
        settle_match = re.fullmatch(r"/payments/([^/]+)/settle", path)
        refund_request_match = re.fullmatch(r"/payments/([^/]+)/refund-request", path)
        refund_match = re.fullmatch(r"/payments/([^/]+)/refund", path)
        refund_reject_match = re.fullmatch(r"/payments/([^/]+)/refund-reject", path)
        if approve_match:
            self.update_payment_status(user, approve_match.group(1), "Approved")
            return
        if reject_match:
            self.update_payment_status(user, reject_match.group(1), "Rejected")
            return
        if cancel_match:
            self.update_payment_status(user, cancel_match.group(1), "Cancelled")
            return
        if settle_match:
            self.update_payment_status(user, settle_match.group(1), "Settled")
            return
        if refund_request_match:
            self.update_payment_status(user, refund_request_match.group(1), "RefundRequested")
            return
        if refund_match:
            self.update_payment_status(user, refund_match.group(1), "Refunded")
            return
        if refund_reject_match:
            self.reject_refund_request(user, refund_reject_match.group(1))
            return

        self.send_error_page(HTTPStatus.NOT_FOUND, "요청 경로를 찾을 수 없습니다.")

    def create_payment(self, user: dict, form: dict[str, list[str]]) -> None:
        if user["role"] != "Customer":
            add_event(user["email"], user["role"], "CREATE_PAYMENT", "Denied", "결제 생성 권한 없음")
            self.send_html(self.forbidden_page(user, {"Customer"}), HTTPStatus.FORBIDDEN)
            return

        merchant = form.get("merchant", [""])[0].strip()
        amount_text = form.get("amount", ["0"])[0].strip()
        memo = form.get("memo", [""])[0].strip()
        try:
            amount = int(amount_text)
        except ValueError:
            amount = 0

        if merchant not in REGISTERED_MERCHANTS:
            self.send_html(self.new_payment_page(user, "등록된 가맹점을 선택해야 합니다."), HTTPStatus.BAD_REQUEST)
            return

        if amount <= 0:
            self.send_html(self.new_payment_page(user, "1원 이상의 금액을 입력해야 합니다."), HTTPStatus.BAD_REQUEST)
            return

        data = load_data()
        payment_id = f"PAY-{1001 + len(data['payments'])}"
        data["payments"].insert(
            0,
            {
                "id": payment_id,
                "merchant": merchant,
                "amount": amount,
                "status": "Pending",
                "created_by": user["email"],
                "created_at": now_iso(),
                "memo": memo,
            },
        )
        save_data(data)
        add_event(user["email"], user["role"], "CREATE_PAYMENT", "Success", f"{payment_id} 생성")
        self.redirect("/payments?msg=created")

    def update_payment_status(self, user: dict, payment_id: str, status: str) -> None:
        allowed_roles = {
            "Approved": {"SettlementOperator"},
            "Rejected": {"SettlementOperator"},
            "RefundRequested": {"Merchant"},
            "Refunded": {"OperationsAdmin"},
            "Cancelled": {"OperationsAdmin"},
            "Settled": {"OperationsAdmin"},
        }.get(status, {"OperationsAdmin"})
        if user["role"] not in allowed_roles:
            add_event(user["email"], user["role"], f"{status.upper()}_PAYMENT", "Denied", "거래 상태 변경 권한 없음")
            self.send_html(self.forbidden_page(user, allowed_roles), HTTPStatus.FORBIDDEN)
            return

        data = load_data()
        for payment in data["payments"]:
            if payment["id"] == payment_id:
                if user["role"] == "Merchant" and payment["merchant"] not in assigned_merchants(user, data):
                    add_event(user["email"], user["role"], f"{status.upper()}_PAYMENT", "Denied", f"{payment_id} 담당 가맹점 아님")
                    self.send_html(self.forbidden_page(user, {"Merchant"}), HTTPStatus.FORBIDDEN)
                    return
                if status in {"Approved", "Rejected"} and payment["status"] != "Pending":
                    self.send_error_page(HTTPStatus.BAD_REQUEST, "승인 대기 결제만 승인 또는 거절할 수 있습니다.")
                    return
                if status == "RefundRequested" and payment["status"] not in {"Approved", "Settled"}:
                    self.send_error_page(HTTPStatus.BAD_REQUEST, "승인 또는 정산 완료 결제만 환불 요청할 수 있습니다.")
                    return
                if status == "Refunded" and payment["status"] != "RefundRequested":
                    self.send_error_page(HTTPStatus.BAD_REQUEST, "환불 요청 상태의 결제만 환불 처리할 수 있습니다.")
                    return
                if status == "Settled" and payment["status"] != "Approved":
                    self.send_error_page(HTTPStatus.BAD_REQUEST, "승인 완료 결제만 정산 완료 처리할 수 있습니다.")
                    return
                if status == "Cancelled" and payment["status"] in {"Refunded", "Settled", "Cancelled"}:
                    self.send_error_page(HTTPStatus.BAD_REQUEST, "이미 최종 처리된 결제는 취소할 수 없습니다.")
                    return
                payment["status"] = status
                payment["reviewed_by"] = user["email"]
                payment["reviewed_at"] = now_iso()
                save_data(data)
                add_event(user["email"], user["role"], f"{status.upper()}_PAYMENT", "Success", f"{payment_id} {status_label(status)} 처리")
                message = {
                    "Approved": "approved",
                    "Rejected": "rejected",
                    "RefundRequested": "refund_requested",
                    "Refunded": "refunded",
                    "Cancelled": "cancelled",
                    "Settled": "settled",
                }.get(status, "updated")
                target = "/payments/review" if status in {"Approved", "Rejected"} else f"/detail?id={payment_id}"
                separator = "&" if "?" in target else "?"
                self.redirect(f"{target}{separator}msg={message}")
                return
        self.send_error_page(HTTPStatus.NOT_FOUND, "결제 건을 찾을 수 없습니다.")

    def reject_refund_request(self, user: dict, payment_id: str) -> None:
        if user["role"] != "OperationsAdmin":
            add_event(user["email"], user["role"], "REJECT_REFUND_REQUEST", "Denied", "환불 반려 권한 없음")
            self.send_html(self.forbidden_page(user, {"OperationsAdmin"}), HTTPStatus.FORBIDDEN)
            return

        data = load_data()
        for payment in data["payments"]:
            if payment["id"] == payment_id:
                if payment["status"] != "RefundRequested":
                    self.send_error_page(HTTPStatus.BAD_REQUEST, "환불 요청 상태의 결제만 환불 반려할 수 있습니다.")
                    return
                payment["status"] = "Approved"
                payment["reviewed_by"] = user["email"]
                payment["reviewed_at"] = now_iso()
                save_data(data)
                add_event(user["email"], user["role"], "REJECT_REFUND_REQUEST", "Success", f"{payment_id} 환불 반려")
                self.redirect(f"/detail?id={payment_id}&msg=refund_rejected")
                return
        self.send_error_page(HTTPStatus.NOT_FOUND, "결제 건을 찾을 수 없습니다.")

    def assign_merchant(self, user: dict, form: dict[str, list[str]]) -> None:
        if user["role"] != "OperationsAdmin":
            add_event(user["email"], user["role"], "ASSIGN_MERCHANT", "Denied", "가맹점 배정 권한 없음")
            self.send_html(self.forbidden_page(user, {"OperationsAdmin"}), HTTPStatus.FORBIDDEN)
            return

        email = form.get("email", [""])[0].strip().lower()
        merchant = form.get("merchant", [""])[0].strip()
        if not email or "@" not in email or merchant not in REGISTERED_MERCHANTS:
            self.send_error_page(HTTPStatus.BAD_REQUEST, "Merchant 이메일과 등록 가맹점을 올바르게 선택해야 합니다.")
            return

        data = load_data()
        assignments = data["merchant_assignments"]
        if not any(a["email"] == email and a["merchant"] == merchant for a in assignments):
            assignments.append({"email": email, "merchant": merchant})
            save_data(data)
            add_event(user["email"], user["role"], "ASSIGN_MERCHANT", "Success", f"{email} -> {merchant}")
        self.redirect("/operations/merchants?msg=merchant_assigned")

    def unassign_merchant(self, user: dict, form: dict[str, list[str]]) -> None:
        if user["role"] != "OperationsAdmin":
            add_event(user["email"], user["role"], "UNASSIGN_MERCHANT", "Denied", "가맹점 배정 해제 권한 없음")
            self.send_html(self.forbidden_page(user, {"OperationsAdmin"}), HTTPStatus.FORBIDDEN)
            return

        email = form.get("email", [""])[0].strip().lower()
        merchant = form.get("merchant", [""])[0].strip()
        data = load_data()
        before = len(data["merchant_assignments"])
        data["merchant_assignments"] = [
            assignment for assignment in data["merchant_assignments"]
            if not (assignment["email"] == email and assignment["merchant"] == merchant)
        ]
        if len(data["merchant_assignments"]) != before:
            save_data(data)
            add_event(user["email"], user["role"], "UNASSIGN_MERCHANT", "Success", f"{email} -> {merchant}")
        self.redirect("/operations/merchants?msg=merchant_unassigned")

    def login_page(self, error: str = "") -> str:
        message = f'<div class="alert danger">{esc(error)}</div>' if error else ""
        login_action = '<div class="alert danger">로그인 서비스가 아직 준비되지 않았습니다.</div>'
        if APP_CONFIG["cognito_hosted_ui_url"]:
            login_action = """
                <a class="button login-primary" href="/auth/cognito/start">로그인</a>
                <p class="muted">발급받은 계정으로 접속하면 업무 권한에 맞는 메뉴가 자동으로 표시됩니다.</p>
            """
        return self.page(
            "로그인",
            None,
            f"""
            <section class="login">
              <div class="login-copy">
                <p class="eyebrow">FinPay Console</p>
                <h1>결제 운영과 보안 감사를 하나의 콘솔에서 관리합니다</h1>
                <p>결제 요청, 승인 처리, 감사 추적을 역할별 권한에 따라 안전하게 운영합니다.</p>
                <div class="login-highlights">
                  <span>역할 기반 접근제어</span>
                  <span>결제 승인 흐름</span>
                  <span>감사 이벤트 추적</span>
                </div>
              </div>
              <section class="panel login-panel">
                <p class="eyebrow">Secure Sign In</p>
                <h2>FinPay 로그인</h2>
                {message}
                {login_action}
                <div class="login-note">
                  <strong>승인된 사용자만 접속할 수 있습니다.</strong>
                  <span>계정 발급과 권한 변경은 운영 관리자에게 요청해 주세요.</span>
                </div>
              </section>
            </section>
            """,
        )

    def dashboard_page(self, user: dict) -> str:
        data = load_data()
        payments = visible_payments(data, user)
        payment_counts = count_by_status(payments)
        pending = payment_counts["Pending"]
        approved = payment_counts["Approved"]
        denied = sum(1 for e in visible_audit_events(data, user) if e["result"] == "Denied")
        total_amount = approved_amount(payments)
        recent_rows = "".join(self.payment_row(p, user) for p in payments[:5]) or '<tr><td colspan="7">표시할 결제가 없습니다.</td></tr>'
        dashboard_focus = {
            "Customer": ("결제 요청", "새 결제 요청을 만들고 본인이 요청한 거래만 확인합니다.", '<a class="button" href="/payments/new">결제 생성</a>'),
            "Merchant": ("가맹점 거래", "배정된 가맹점의 승인 거래와 정산 결과만 확인합니다.", '<a class="button" href="/merchant/settlements">정산 조회</a>'),
            "SettlementOperator": ("승인 처리", "승인 대기 거래를 승인 또는 거절하는 업무만 담당합니다.", '<a class="button" href="/payments/review">승인 대기 보기</a>'),
            "Auditor": ("감사 조회", "결제와 감사 이벤트를 읽기 전용으로 확인합니다.", '<a class="button" href="/audit/events">감사 이벤트</a>'),
            "OperationsAdmin": ("운영 관리", "가맹점 배정과 승인 이후 정산, 취소, 환불 처리를 담당합니다.", '<a class="button" href="/merchant/settlements">정산 처리</a>'),
        }[user["role"]]
        return self.page(
            "대시보드",
            user,
            f"""
            <div class="grid metrics">
              {self.metric("표시 결제", len(payments))}
              {self.metric("승인 대기", pending)}
              {self.metric("승인 완료", approved)}
              {self.metric("승인 결제 금액", format_money(total_amount))}
            </div>
            <section class="panel hero-panel">
              <div>
                <h2>{dashboard_focus[0]}</h2>
                <p>{dashboard_focus[1]}</p>
              </div>
              {dashboard_focus[2]}
            </section>
            <section class="grid">
              {self.status_card("표시 범위", "역할 기준", "현재 계정에 허용된 거래와 메뉴만 표시됩니다.")}
              {self.status_card("승인 대기", f"{pending}건", "승인이 필요한 거래 수입니다.")}
              {self.status_card("접근 차단", f"{denied}건", "권한 없는 접근은 차단되고 감사 이벤트로 남습니다.")}
            </section>
            <section class="panel">
              <h2>결제 상태 분포</h2>
              {self.distribution(payment_counts)}
            </section>
            <section class="panel">
              <h2>최근 결제</h2>
              <table>
                <thead><tr><th>ID</th><th>상태</th><th>가맹점</th><th>금액</th><th>생성 시간</th><th>생성자</th><th>상세</th></tr></thead>
                <tbody>{recent_rows}</tbody>
              </table>
            </section>
            """,
        )

    def my_access_page(self, user: dict) -> str:
        allowed_rows = "".join(
            f"<tr><td>{esc(label)}</td><td><code>{esc(path)}</code></td></tr>"
            for label, path in allowed_nav_items(user)
        )
        allowed_api_rows = "".join(
            f"<tr><td><code>{esc(api)}</code></td></tr>"
            for api in ROLE_ALLOWED_APIS[user["role"]]
        )
        allowed_api_count = len(ROLE_ALLOWED_APIS[user["role"]])
        merchant_scope = ", ".join(sorted(assigned_merchants(user))) if user["role"] == "Merchant" else "해당 없음"
        denied_rows = "".join(
            f"<tr><td>{esc(label)}</td><td><code>{esc(path)}</code></td></tr>"
            for label, path, roles in NAV_ITEMS
            if user["role"] not in roles
        ) or '<tr><td colspan="2">차단된 메뉴가 없습니다.</td></tr>'
        return self.page(
            "내 권한",
            user,
            f"""
            <section class="grid">
              {self.status_card("사용자", user["email"], "로그인 계정")}
              {self.status_card("역할", user["role"], ROLE_DESCRIPTIONS[user["role"]])}
              {self.status_card("허용 API", f"{allowed_api_count}개", "아래 목록의 API만 현재 역할에서 사용할 수 있습니다.")}
            </section>
            {"".join([f'<section class="panel"><h2>담당 가맹점</h2><p>{esc(merchant_scope)}</p></section>']) if user["role"] == "Merchant" else ""}
            <section class="panel">
              <h2>허용된 메뉴</h2>
              <table>
                <thead><tr><th>기능</th><th>경로</th></tr></thead>
                <tbody>{allowed_rows}</tbody>
              </table>
            </section>
            <section class="panel">
              <h2>허용된 API</h2>
              <table>
                <thead><tr><th>API</th></tr></thead>
                <tbody>{allowed_api_rows}</tbody>
              </table>
            </section>
            <section class="panel">
              <h2>차단된 메뉴</h2>
              <table>
                <thead><tr><th>기능</th><th>경로</th></tr></thead>
                <tbody>{denied_rows}</tbody>
              </table>
            </section>
            """,
        )

    def new_payment_page(self, user: dict, error: str = "") -> str:
        message = f'<div class="alert danger">{esc(error)}</div>' if error else ""
        merchant_options = "".join(
            f'<option value="{esc(merchant)}">{esc(merchant)}</option>'
            for merchant in REGISTERED_MERCHANTS
        )
        return self.page(
            "결제 생성",
            user,
            f"""
            <section class="panel narrow">
              <h2>새 결제 요청</h2>
              {message}
              <form method="post" action="/payments" class="stack">
                <label>가맹점</label>
                <select name="merchant" required>{merchant_options}</select>
                <label>금액</label>
                <input name="amount" type="number" min="1" value="75000" required>
                <label>메모</label>
                <textarea name="memo">정산 승인 요청</textarea>
                <button type="submit">결제 요청 생성</button>
              </form>
            </section>
            """,
        )

    def review_payments_page(self, user: dict) -> str:
        data = load_data()
        rows = [
            p for p in data["payments"] if p["status"] == "Pending"
        ]
        body = "".join(self.payment_review_row(p) for p in rows) or '<tr><td colspan="5">승인 대기 결제가 없습니다.</td></tr>'
        notice = self.flash_message()
        return self.page(
            "결제 승인",
            user,
            f"""
            <section class="panel">
              <h2>승인 대기 결제</h2>
              {notice}
              <table>
                <thead><tr><th>ID</th><th>가맹점</th><th>금액</th><th>요청자</th><th>처리</th></tr></thead>
                <tbody>{body}</tbody>
              </table>
            </section>
            """,
        )

    def payment_history_page(self, user: dict) -> str:
        params = parse_qs(urlparse(self.path).query)
        selected_status = params.get("status", ["All"])[0]
        keyword = params.get("q", [""])[0].strip()
        data = load_data()
        payments = filter_payments(visible_payments(data, user), selected_status, keyword)
        payment_counts = count_by_status(payments)
        status_options = "".join(
            f'<option value="{esc(value)}" {"selected" if selected_status == value else ""}>{esc(status_label(value) if value != "All" else "All")}</option>'
            for value in ["All", *PAYMENT_STATUSES]
        )
        rows = "".join(self.payment_row(p, user) for p in payments) or '<tr><td colspan="7">표시할 결제가 없습니다.</td></tr>'
        notice = self.flash_message()
        return self.page(
            "결제 내역",
            user,
            f"""
            <section class="panel">
              <h2>결제 내역</h2>
              {notice}
              <p class="muted">현재 역할에서 조회 가능한 결제만 표시됩니다.</p>
              <div class="toolbar"><a class="button secondary" href="/export/payments.csv">CSV 내보내기</a></div>
              {self.distribution(payment_counts)}
              <form method="get" action="/payments" class="filters">
                <label>상태</label>
                <select name="status">{status_options}</select>
                <label>검색어</label>
                <input name="q" value="{esc(keyword)}" placeholder="결제 ID, 가맹점, 생성자, 메모">
                <button type="submit">필터 적용</button>
                <a class="button secondary" href="/payments">초기화</a>
              </form>
              <table>
                <thead><tr><th>ID</th><th>상태</th><th>가맹점</th><th>금액</th><th>생성 시간</th><th>생성자</th><th>상세</th></tr></thead>
                <tbody>{rows}</tbody>
              </table>
            </section>
            """,
        )

    def payment_detail_from_query_page(self, user: dict) -> str:
        payment_id = parse_qs(urlparse(self.path).query).get("id", [""])[0]
        body, _status = self.payment_detail_page(user, payment_id)
        return body

    def payment_detail_page(self, user: dict, payment_id: str) -> tuple[str, HTTPStatus]:
        data = load_data()
        payment = find_visible_payment(data, user, payment_id)
        if not payment:
            add_event(user["email"], user["role"], "VIEW_PAYMENT", "Denied", f"{payment_id} 조회 권한 없음")
            return self.forbidden_page(user, {"Customer", "Merchant", "SettlementOperator", "Auditor", "OperationsAdmin"}), HTTPStatus.FORBIDDEN

        review = ""
        if payment["status"] == "Pending" and user["role"] == "SettlementOperator":
            review = f"""
            <section class="action-panel">
              <h2>승인 처리</h2>
              <p>승인 대기 거래를 검토한 뒤 승인 또는 거절합니다.</p>
              <div class="actions detail-actions">
                <form method="post" action="/payments/{esc(payment["id"])}/approve"><button type="submit">승인</button></form>
                <form method="post" action="/payments/{esc(payment["id"])}/reject"><button type="submit" class="danger-btn">거절</button></form>
              </div>
            </section>
            """
        if payment["status"] in {"Approved", "Settled"} and user["role"] == "Merchant" and payment["merchant"] in assigned_merchants(user, data):
            review += f"""
            <section class="action-panel">
              <h2>환불 요청</h2>
              <p>고객 응대 또는 거래 취소 사유가 있을 때 운영 관리자에게 환불 처리를 요청합니다.</p>
              <div class="actions detail-actions">
                <form method="post" action="/payments/{esc(payment["id"])}/refund-request"><button type="submit" class="secondary">환불 요청</button></form>
              </div>
            </section>
            """
        if payment["status"] == "Approved" and user["role"] == "OperationsAdmin":
            review += f"""
            <section class="action-panel">
              <h2>정산 처리</h2>
              <p>승인 완료 거래를 정산 완료로 전환하거나 운영 사유로 취소합니다.</p>
              <div class="actions detail-actions">
                <form method="post" action="/payments/{esc(payment["id"])}/settle"><button type="submit">정산 완료</button></form>
                <form method="post" action="/payments/{esc(payment["id"])}/cancel"><button type="submit" class="danger-btn">거래 취소</button></form>
              </div>
            </section>
            """
        if payment["status"] == "RefundRequested" and user["role"] == "OperationsAdmin":
            review += f"""
            <section class="action-panel refund-panel">
              <h2>환불 검토</h2>
              <p>가맹점이 요청한 환불 건을 확인한 뒤 완료 또는 반려 처리합니다.</p>
              <div class="actions detail-actions">
                <form method="post" action="/payments/{esc(payment["id"])}/refund"><button type="submit">환불 완료</button></form>
                <form method="post" action="/payments/{esc(payment["id"])}/refund-reject"><button type="submit" class="secondary">환불 반려</button></form>
              </div>
            </section>
            """

        timeline = "".join(
            f"""
            <tr>
              <td class="time-cell">{esc(format_datetime(event["time"]))}</td>
              <td>{esc(actor_label(user, event["actor"]))}</td>
              <td>{esc(event["action"])}</td>
              <td><span class="badge {esc(event["result"].lower())}">{esc(event["result"])}</span></td>
              <td>{esc(event["detail"])}</td>
            </tr>
            """
            for event in data["audit_events"]
            if payment_id in event["detail"]
        ) or '<tr><td colspan="5">이 결제와 연결된 감사 이벤트가 없습니다.</td></tr>'

        add_event(user["email"], user["role"], "VIEW_PAYMENT", "Success", f"{payment_id} 상세 조회")
        return self.page(
            "결제 상세",
            user,
            f"""
            <section class="panel detail">
              <div class="detail-head">
                <div>
                  <p class="eyebrow">Payment Detail</p>
                  <h2>{esc(payment["id"])}</h2>
                </div>
                <span class="badge {esc(payment["status"].lower())}">{esc(status_label(payment["status"]))}</span>
              </div>
              <dl>
                <dt>가맹점</dt><dd>{esc(payment["merchant"])}</dd>
                <dt>금액</dt><dd>{esc(format_money(payment["amount"]))}</dd>
                <dt>생성자</dt><dd>{esc(actor_label(user, payment["created_by"]))}</dd>
                <dt>생성 시간</dt><dd class="time-cell">{esc(format_datetime(payment["created_at"]))}</dd>
                <dt>메모</dt><dd>{esc(payment.get("memo", ""))}</dd>
                <dt>처리자</dt><dd>{esc(actor_label(user, payment.get("reviewed_by", "-")))}</dd>
                <dt>처리 시간</dt><dd class="time-cell">{esc(format_datetime(payment.get("reviewed_at", "-")))}</dd>
              </dl>
              {review}
              <a class="button secondary" href="/payments">목록으로</a>
            </section>
            <section class="panel detail">
              <h2>처리 이력</h2>
              <table>
                <thead><tr><th>시간</th><th>사용자</th><th>행위</th><th>결과</th><th>상세</th></tr></thead>
                <tbody>{timeline}</tbody>
              </table>
            </section>
            """,
        ), HTTPStatus.OK

    def audit_events_page(self, user: dict) -> str:
        params = parse_qs(urlparse(self.path).query)
        selected_result = params.get("result", ["All"])[0]
        selected_action = params.get("action", [""])[0].strip()
        data = load_data()
        events = data["audit_events"]
        all_events = list(events)
        result_counts = count_by_result(all_events)
        if selected_result != "All":
            events = [e for e in events if e["result"] == selected_result]
        if selected_action:
            keyword = selected_action.lower()
            events = [e for e in events if keyword in e["action"].lower() or keyword in e["detail"].lower()]

        result_options = "".join(
            f'<option value="{esc(value)}" {"selected" if selected_result == value else ""}>{esc(value)}</option>'
            for value in ["All", "Success", "Denied"]
        )
        rows = "".join(
            f"""
            <tr>
              <td class="time-cell">{esc(format_datetime(e["time"]))}</td>
              <td>{esc(actor_label(user, e["actor"]))}</td>
              <td>{esc(e["role"])}</td>
              <td>{esc(e["action"])}</td>
              <td><span class="badge {esc(e["result"].lower())}">{esc(e["result"])}</span></td>
              <td>{esc(e["detail"])}</td>
            </tr>
            """
            for e in events[:80]
        ) or '<tr><td colspan="6">조건에 맞는 감사 이벤트가 없습니다.</td></tr>'
        return self.page(
            "감사 이벤트",
            user,
            f"""
            <div class="grid metrics">
              {self.metric("전체 이벤트", len(all_events))}
              {self.metric("성공", result_counts["Success"])}
              {self.metric("차단", result_counts["Denied"])}
              {self.metric("표시 이벤트", len(events))}
            </div>
            <section class="panel">
              <h2>감사 결과 분포</h2>
              {self.distribution(result_counts)}
            </section>
            <section class="panel">
              <h2>감사 이벤트</h2>
              <div class="toolbar"><a class="button secondary" href="/export/audit-events.csv">CSV 내보내기</a></div>
              <form method="get" action="/audit/events" class="filters">
                <label>결과</label>
                <select name="result">{result_options}</select>
                <label>검색어</label>
                <input name="action" value="{esc(selected_action)}" placeholder="행위 또는 상세 내용">
                <button type="submit">필터 적용</button>
                <a class="button secondary" href="/audit/events">초기화</a>
              </form>
              <table>
                <thead><tr><th>시간</th><th>사용자</th><th>역할</th><th>행위</th><th>결과</th><th>상세</th></tr></thead>
                <tbody>{rows}</tbody>
              </table>
            </section>
            """,
        )

    def merchant_settlements_page(self, user: dict) -> str:
        data = load_data()
        payments = visible_payments(data, user)
        assigned = sorted(assigned_merchants(user, data)) if user["role"] == "Merchant" else REGISTERED_MERCHANTS
        rows = ""
        for merchant_name in assigned:
            merchant_payments = [p for p in payments if p["merchant"] == merchant_name]
            counts = count_by_status(merchant_payments)
            rows += f"""
            <tr>
              <td>{esc(merchant_name)}</td>
              <td>{len(merchant_payments)}</td>
              <td>{counts["Approved"]}</td>
              <td>{counts["Settled"]}</td>
              <td>{counts["RefundRequested"]}</td>
              <td>{esc(format_money(approved_amount(merchant_payments)))}</td>
              <td>{esc(format_money(settlement_amount(merchant_payments)))}</td>
            </tr>
            """
        if user["role"] == "OperationsAdmin":
            pending_settlement_rows = "".join(
                self.settlement_action_row(p)
                for p in payments
                if p["status"] == "Approved"
            ) or '<tr><td colspan="7">정산 대기 거래가 없습니다.</td></tr>'
            completed_settlement_rows = "".join(
                self.payment_row(p, user)
                for p in payments
                if p["status"] == "Settled"
            ) or '<tr><td colspan="7">정산 완료 거래가 없습니다.</td></tr>'
            action_section = f"""
            <section class="panel">
              <h2>정산 대기 거래</h2>
              <p class="muted">승인 완료된 거래를 이 화면에서 바로 정산 완료 처리합니다.</p>
              <table>
                <thead><tr><th>ID</th><th>가맹점</th><th>금액</th><th>생성 시간</th><th>생성자</th><th>상세</th><th>처리</th></tr></thead>
                <tbody>{pending_settlement_rows}</tbody>
              </table>
            </section>
            <section class="panel">
              <h2>정산 완료 이력</h2>
              <table>
                <thead><tr><th>ID</th><th>상태</th><th>가맹점</th><th>금액</th><th>생성 시간</th><th>생성자</th><th>상세</th></tr></thead>
                <tbody>{completed_settlement_rows}</tbody>
              </table>
            </section>
            """
        else:
            merchant_payment_rows = "".join(
                self.payment_row(p, user)
                for p in payments
                if p["status"] in {"Approved", "Settled"}
            ) or '<tr><td colspan="7">표시할 승인 또는 정산 완료 거래가 없습니다.</td></tr>'
            action_section = f"""
            <section class="panel">
              <h2>정산 대상 거래</h2>
              <table>
                <thead><tr><th>ID</th><th>상태</th><th>가맹점</th><th>금액</th><th>생성 시간</th><th>생성자</th><th>상세</th></tr></thead>
                <tbody>{merchant_payment_rows}</tbody>
              </table>
            </section>
            """
        return self.page(
            "정산 조회",
            user,
            f"""
            <div class="grid metrics">
              {self.metric("담당 가맹점", len(assigned))}
              {self.metric("승인 결제 금액", format_money(approved_amount(payments)))}
              {self.metric("정산 완료 금액", format_money(settlement_amount(payments)))}
              {self.metric("정산 대기", count_by_status(payments)["Approved"])}
            </div>
            <section class="panel">
              <h2>가맹점별 정산 요약</h2>
              <table>
                <thead><tr><th>가맹점</th><th>전체 건수</th><th>승인</th><th>정산 완료</th><th>환불 요청</th><th>승인 금액</th><th>정산 금액</th></tr></thead>
                <tbody>{rows}</tbody>
              </table>
            </section>
            {action_section}
            """,
        )

    def security_status_page(self, user: dict) -> str:
        status = integration_status()
        cognito_state = "설정됨" if status["cognito"]["configured"] else "미설정"
        cloudwatch_state = "설정됨" if status["cloudwatch"]["configured"] else "미설정"
        secret_state = "설정됨" if status["secrets_manager"]["configured"] else "미설정"
        return self.page(
            "보안 상태",
            user,
            f"""
            <div class="grid">
              {self.status_card("로그인 연동", cognito_state, "사용자 그룹을 앱 역할로 매핑합니다.")}
              {self.status_card("비밀값 보관", secret_state, "데이터베이스 비밀번호를 앱 코드와 분리합니다.")}
              {self.status_card("운영 로그", cloudwatch_state, "로그인, 결제 처리, 접근 거부 이벤트를 전송합니다.")}
            </div>
            <section class="panel">
              <h2>접근 제어 기준</h2>
              <table>
                <thead><tr><th>역할</th><th>주요 허용 기능</th></tr></thead>
                <tbody>
                  <tr><td>Customer</td><td>등록 가맹점 선택 후 본인 결제 요청 생성 및 조회</td></tr>
                  <tr><td>Merchant</td><td>담당 가맹점 거래/정산 조회 및 환불 요청</td></tr>
                  <tr><td>SettlementOperator</td><td>승인 대기 결제 승인 또는 거절 전담</td></tr>
                  <tr><td>Auditor</td><td>결제 내역 및 감사 이벤트 조회</td></tr>
                  <tr><td>OperationsAdmin</td><td>가맹점 관리, 환불/취소/정산 처리, 운영 상태 확인</td></tr>
                </tbody>
              </table>
            </section>
            """,
        )

    def merchant_admin_page(self, user: dict) -> str:
        data = load_data()
        assignments_by_email = merchant_assignment_map(data)
        assignments = {merchant_name: [] for merchant_name in REGISTERED_MERCHANTS}
        for email, merchant_names in assignments_by_email.items():
            for merchant_name in merchant_names:
                if merchant_name in assignments:
                    assignments[merchant_name].append(email)
        merchant_account_count = len(assignments_by_email)
        merchant_options = "".join(
            f'<option value="{esc(merchant_name)}">{esc(merchant_name)}</option>'
            for merchant_name in REGISTERED_MERCHANTS
        )
        rows = ""
        for merchant_name in REGISTERED_MERCHANTS:
            payments = [p for p in data["payments"] if p["merchant"] == merchant_name]
            counts = count_by_status(payments)
            assigned_emails = sorted(assignments.get(merchant_name, []))
            assigned = ", ".join(assigned_emails) or "미배정"
            unassign_actions = "".join(
                f"""
                <form method="post" action="/operations/merchants/unassign" class="inline-form">
                  <input type="hidden" name="email" value="{esc(email)}">
                  <input type="hidden" name="merchant" value="{esc(merchant_name)}">
                  <button type="submit" class="small secondary">해제</button>
                </form>
                """
                for email in assigned_emails
            ) or "-"
            rows += f"""
            <tr>
              <td>{esc(merchant_name)}</td>
              <td>{esc(assigned)}</td>
              <td>{len(payments)}</td>
              <td>{counts["Pending"]}</td>
              <td>{counts["Approved"]}</td>
              <td>{counts["Settled"]}</td>
              <td>{counts["Rejected"]}</td>
              <td>{esc(format_money(approved_amount(payments)))}</td>
              <td>{esc(format_money(settlement_amount(payments)))}</td>
              <td>{unassign_actions}</td>
            </tr>
            """
        notice = self.flash_message()
        return self.page(
            "가맹점 관리",
            user,
            f"""
            <section class="grid">
              {self.metric("등록 가맹점", len(REGISTERED_MERCHANTS))}
              {self.metric("Merchant 계정", merchant_account_count)}
              {self.metric("승인 결제 금액", format_money(approved_amount(data["payments"])))}
              {self.metric("정산 완료 금액", format_money(settlement_amount(data["payments"])))}
            </section>
            <section class="panel hero-panel">
              <div>
                <h2>가맹점 접근 범위</h2>
                <p>OperationsAdmin은 Merchant 계정에 담당 가맹점을 배정하고, Merchant는 배정된 가맹점 거래와 정산 내역만 조회합니다.</p>
              </div>
            </section>
            {notice}
            <section class="panel narrow">
              <h2>Merchant 가맹점 배정</h2>
              <form method="post" action="/operations/merchants/assign" class="stack">
                <label>Merchant 이메일</label>
                <input name="email" type="email" value="{esc(DEFAULT_MERCHANT_EMAIL)}" required>
                <label>가맹점</label>
                <select name="merchant" required>{merchant_options}</select>
                <button type="submit">가맹점 배정</button>
              </form>
            </section>
            <section class="panel">
              <h2>등록 가맹점 및 담당자</h2>
              <table>
                <thead><tr><th>가맹점</th><th>담당 Merchant</th><th>전체 건수</th><th>Pending</th><th>Approved</th><th>Settled</th><th>Rejected</th><th>승인 금액</th><th>정산 금액</th><th>배정 해제</th></tr></thead>
                <tbody>{rows}</tbody>
              </table>
            </section>
            <section class="panel">
              <h2>운영 기준</h2>
              <table>
                <thead><tr><th>대상</th><th>정책</th></tr></thead>
                <tbody>
                  <tr><td>가맹점 등록</td><td>OperationsAdmin이 등록한 가맹점만 결제 생성 화면에 표시됩니다.</td></tr>
                  <tr><td>Merchant 배정</td><td>Merchant 계정은 배정된 가맹점의 결제만 조회할 수 있습니다.</td></tr>
                  <tr><td>거래 승인</td><td>SettlementOperator만 승인 대기 결제를 승인 또는 거절합니다.</td></tr>
                  <tr><td>사후 처리</td><td>OperationsAdmin은 승인 이후 결제를 정산 완료, 취소, 환불 상태로 변경합니다.</td></tr>
                  <tr><td>감사</td><td>Auditor와 OperationsAdmin만 전체 감사 이벤트를 확인합니다.</td></tr>
                </tbody>
              </table>
            </section>
            """,
        )

    def system_status_page(self, user: dict) -> str:
        status = integration_status()
        rds = status["rds"]
        secret_state = "설정됨" if status["secrets_manager"]["configured"] else "미설정"
        rds_state = "연결 가능" if rds["status"] == "reachable" else "확인 필요"
        return self.page(
            "시스템 상태",
            user,
            f"""
            <div class="grid">
              {self.status_card("서비스 런타임", "정상", "애플리케이션 프로세스가 실행 중입니다.")}
              {self.status_card("데이터 저장", "운영 DB", status["storage"]["warning"] or "정상")}
              {self.status_card("데이터베이스", rds_state, "VPC 내부 앱 서버에서만 연결 상태를 확인합니다.")}
              {self.status_card("보안 저장소", secret_state, "민감정보는 관리형 비밀 저장소에서 조회합니다.")}
              {self.status_card("운영 로그", "설정됨" if status["cloudwatch"]["configured"] else "미설정", "주요 서비스 이벤트를 운영 로그로 전송합니다.")}
            </div>
            <section class="panel">
              <h2>서비스 연동 상태</h2>
              <div class="kv-grid">
                {self.kv_item("인증", "연동됨" if status["cognito"]["configured"] else "미설정")}
                {self.kv_item("데이터베이스", rds_state)}
                {self.kv_item("비밀값 저장소", secret_state)}
                {self.kv_item("운영 로그", "연동됨" if status["cloudwatch"]["configured"] else "미설정")}
                {self.kv_item("응답 지연", str(rds.get("latency_ms", "-")) + (" ms" if "latency_ms" in rds else ""))}
              </div>
            </section>
            """,
        )

    def forbidden_page(self, user: dict, allowed_roles: set[str]) -> str:
        return self.page(
            "접근 거부",
            user,
            f"""
            <section class="panel narrow">
              <h2>403 접근 거부</h2>
              <p>현재 역할 <strong>{esc(user["role"])}</strong> 은 이 기능을 사용할 수 없습니다.</p>
              <p>허용 역할: {esc(", ".join(sorted(allowed_roles)))}</p>
              <a class="button secondary" href="/dashboard">대시보드로 이동</a>
            </section>
            """,
        )

    def page(self, title: str, user: dict | None, body: str) -> str:
        nav = ""
        userbar = ""
        if user:
            current_path = urlparse(self.path).path
            links = "".join(
                f'<a class="{"active" if current_path == path else ""}" href="{path}">{label}</a>'
                for label, path in allowed_nav_items(user)
            )
            nav = f"<nav>{links}</nav>"
            userbar = f"""
            <form method="post" action="/auth/logout" class="userbar">
              {self.csrf_input(user)}
              <span>{esc(user["name"])} · {esc(user["role"])}</span>
              <button type="submit" class="small">로그아웃</button>
            </form>
            """
            body = self.inject_csrf_tokens(body, self.csrf_input(user))

        return f"""<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>FinPay - {esc(title)}</title>
  <style>{STYLE}</style>
</head>
<body>
  <header>
    <a class="brand" href="/dashboard">FinPay</a>
    {nav}
    {userbar}
  </header>
  <main>
    <div class="title"><p class="eyebrow">FinPay Operations</p><h1>{esc(title)}</h1></div>
    {body}
  </main>
</body>
</html>"""

    def payment_row(self, p: dict, user: dict) -> str:
        return f"""
        <tr>
          <td>{esc(p["id"])}</td>
          <td><span class="badge {esc(p["status"].lower())}">{esc(status_label(p["status"]))}</span></td>
          <td>{esc(p["merchant"])}</td>
          <td>{esc(format_money(p["amount"]))}</td>
          <td class="time-cell">{esc(format_datetime(p["created_at"]))}</td>
          <td>{esc(actor_label(user, p["created_by"]))}</td>
          <td><a href="/detail?id={esc(p["id"])}">보기</a></td>
        </tr>
        """

    def payment_review_row(self, p: dict) -> str:
        return f"""
        <tr>
          <td><a href="/detail?id={esc(p["id"])}">{esc(p["id"])}</a></td>
          <td>{esc(p["merchant"])}</td>
          <td>{esc(format_money(p["amount"]))}</td>
          <td>{esc(p["created_by"])}</td>
          <td class="actions">
            <form method="post" action="/payments/{esc(p["id"])}/approve"><button type="submit">승인</button></form>
            <form method="post" action="/payments/{esc(p["id"])}/reject"><button type="submit" class="danger-btn">거절</button></form>
          </td>
        </tr>
        """

    def settlement_action_row(self, p: dict) -> str:
        return f"""
        <tr>
          <td><a href="/detail?id={esc(p["id"])}">{esc(p["id"])}</a></td>
          <td>{esc(p["merchant"])}</td>
          <td>{esc(format_money(p["amount"]))}</td>
          <td class="time-cell">{esc(format_datetime(p["created_at"]))}</td>
          <td>{esc(p["created_by"])}</td>
          <td><a href="/detail?id={esc(p["id"])}">보기</a></td>
          <td>
            <form method="post" action="/payments/{esc(p["id"])}/settle">
              <button type="submit" class="small">정산 완료</button>
            </form>
          </td>
        </tr>
        """

    def metric(self, label: str, value: int) -> str:
        return f'<article class="panel metric"><span>{esc(label)}</span><strong>{esc(value)}</strong></article>'

    def status_card(self, title: str, state: str, detail: str) -> str:
        return f'<article class="panel"><h2>{esc(title)}</h2><p class="state">{esc(state)}</p><p>{esc(detail)}</p></article>'

    def kv_item(self, label: str, value: object) -> str:
        return f'<div class="kv-item"><span>{esc(label)}</span><strong>{esc(value)}</strong></div>'

    def distribution(self, counts: dict[str, int]) -> str:
        total = sum(counts.values())
        if total == 0:
            return '<p class="muted">표시할 데이터가 없습니다.</p>'
        rows = ""
        for label, count in counts.items():
            percent = round((count / total) * 100)
            rows += f"""
            <div class="bar-row">
              <span>{esc(status_label(label))}</span>
              <div class="bar"><i style="width: {percent}%"></i></div>
              <strong>{count}</strong>
            </div>
            """
        return f'<div class="bars">{rows}</div>'

    def flash_message(self) -> str:
        code = parse_qs(urlparse(self.path).query).get("msg", [""])[0]
        messages = {
            "created": ("success", "결제 요청이 생성되었습니다."),
            "approved": ("success", "결제 요청이 승인되었습니다."),
            "rejected": ("danger", "결제 요청이 거절되었습니다."),
            "refund_requested": ("success", "환불 요청이 접수되었습니다."),
            "refunded": ("success", "환불 처리가 완료되었습니다."),
            "refund_rejected": ("success", "환불 요청이 반려되었습니다."),
            "cancelled": ("danger", "거래가 취소되었습니다."),
            "settled": ("success", "정산 완료 처리되었습니다."),
            "updated": ("success", "거래 상태가 변경되었습니다."),
            "merchant_assigned": ("success", "Merchant 가맹점 배정이 저장되었습니다."),
            "merchant_unassigned": ("success", "Merchant 가맹점 배정이 해제되었습니다."),
        }
        if code not in messages:
            return ""
        level, text = messages[code]
        return f'<div class="alert {level}">{esc(text)}</div>'

    def current_user(self) -> dict | None:
        cookie = SimpleCookie(self.headers.get("Cookie", ""))
        morsel = cookie.get("finpay_session")
        if not morsel:
            return None
        user = SESSIONS.get(morsel.value)
        if not user:
            return None
        user["role"] = normalize_role(user.get("role", ""))
        return user

    def require_login(self) -> dict | None:
        user = self.current_user()
        if not user:
            self.redirect("/login")
            return None
        return user

    def csrf_token_for(self, user: dict) -> str:
        token = user.get("csrf_token")
        if not token:
            token = secrets.token_urlsafe(32)
            user["csrf_token"] = token
        return token

    def csrf_input(self, user: dict) -> str:
        return f'<input type="hidden" name="csrf_token" value="{esc(self.csrf_token_for(user))}">'

    def inject_csrf_tokens(self, body: str, csrf_input: str) -> str:
        def add_token(match: re.Match[str]) -> str:
            form_tag = match.group(0)
            if "csrf_token" in form_tag:
                return form_tag
            return f"{form_tag}\n                {csrf_input}"

        return re.sub(r'<form\b(?=[^>]*method="post")[^>]*>', add_token, body, flags=re.IGNORECASE)

    def valid_csrf_token(self, form: dict[str, list[str]]) -> bool:
        user = self.current_user()
        if not user:
            return False
        expected = self.csrf_token_for(user)
        actual = form.get("csrf_token", [""])[0]
        return bool(actual) and secrets.compare_digest(expected, actual)

    def reject_csrf(self, user: dict) -> None:
        add_event(user["email"], user["role"], "CSRF_VALIDATION", "Denied", "POST request CSRF token validation failed")
        self.send_error_page(HTTPStatus.FORBIDDEN, "Request validation failed. Refresh the page and try again.")

    def read_form(self) -> dict[str, list[str]]:
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length).decode("utf-8")
        return parse_qs(raw)

    def session_cookie_header(self, value: str, max_age: int | None = None) -> str:
        parts = [f"finpay_session={value}", "HttpOnly", "SameSite=Lax", "Path=/"]
        if max_age is not None:
            parts.insert(1, f"Max-Age={max_age}")
        if is_secure_request(self.headers):
            parts.insert(-1, "Secure")
        return "; ".join(parts)

    def send_security_headers(self) -> None:
        if is_secure_request(self.headers):
            self.send_header("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
        self.send_header("Content-Security-Policy", "default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; form-action 'self'; frame-ancestors 'none'; base-uri 'self'")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "strict-origin-when-cross-origin")
        self.send_header("Permissions-Policy", "geolocation=(), microphone=(), camera=()")

    def send_html(self, body: str, status: HTTPStatus = HTTPStatus.OK) -> None:
        payload = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_security_headers()
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def send_json(self, body: dict, status: HTTPStatus = HTTPStatus.OK) -> None:
        payload = json.dumps(body, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_security_headers()
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def send_csv(self, filename: str, content: str) -> None:
        payload = content.encode("utf-8-sig")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/csv; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
        self.send_security_headers()
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def send_error_page(self, status: HTTPStatus, message: str) -> None:
        self.send_html(
            self.page(status.phrase, self.current_user(), f'<section class="panel narrow"><h2>{status.value}</h2><p>{esc(message)}</p></section>'),
            status,
        )

    def redirect(self, location: str) -> None:
        self.send_response(HTTPStatus.SEE_OTHER)
        self.send_header("Location", location)
        self.send_security_headers()
        self.end_headers()

    def log_message(self, format: str, *args: object) -> None:
        return


STYLE = """
:root {
  color-scheme: light;
  --bg: #eef3f7;
  --surface: #ffffff;
  --surface-soft: #f8fafc;
  --line: #d5dde7;
  --line-strong: #b8c4d3;
  --text: #101828;
  --muted: #5f6f85;
  --primary: #0f766e;
  --primary-dark: #115e59;
  --accent: #3155a4;
  --danger: #b42318;
  --warning: #b54708;
  --success: #027a48;
  --shadow: 0 10px 24px rgba(16, 24, 40, .08);
}
* { box-sizing: border-box; }
body { margin: 0; font-family: Arial, "Malgun Gothic", sans-serif; background: var(--bg); color: var(--text); font-size: 15px; }
body::before { content: ""; position: fixed; inset: 0 0 auto 0; height: 260px; background: linear-gradient(135deg, #0f1f2e 0%, #0f766e 54%, #3155a4 100%); z-index: -2; }
body::after { content: ""; position: fixed; inset: 220px 0 0 0; background: var(--bg); z-index: -2; }
header { min-height: 68px; display: flex; align-items: center; gap: 18px; padding: 0 28px; background: #0f1f2e; border-bottom: 1px solid #20364b; position: sticky; top: 0; z-index: 10; box-shadow: 0 2px 10px rgba(16, 24, 40, .12); }
.brand { font-weight: 900; font-size: 22px; color: #ffffff; text-decoration: none; letter-spacing: .2px; }
nav { display: flex; gap: 6px; flex-wrap: wrap; flex: 1; }
nav a { color: #dbe6f3; text-decoration: none; padding: 9px 11px; border-radius: 6px; font-size: 14px; }
nav a:hover { background: #1d3449; color: #ffffff; }
nav a.active { background: #ffffff; color: #0f1f2e; }
.button { color: white; text-decoration: none; padding: 10px 14px; border-radius: 6px; font-size: 14px; }
.userbar { display: flex; gap: 10px; align-items: center; color: #dbe6f3; font-size: 13px; }
main { max-width: 1180px; margin: 0 auto; padding: 30px 22px 56px; }
.title { display: flex; align-items: flex-end; justify-content: space-between; gap: 18px; margin-bottom: 18px; padding: 18px 0 20px; color: #ffffff; }
.title .eyebrow { color: #b7f7ed; }
.eyebrow { margin: 0 0 6px; color: var(--accent); text-transform: uppercase; letter-spacing: .04em; font-size: 12px; font-weight: 800; }
h1 { margin: 0; font-size: 30px; line-height: 1.2; }
h2 { margin: 0 0 14px; font-size: 18px; line-height: 1.35; }
p { line-height: 1.65; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 14px; margin-bottom: 16px; }
.panel { background: var(--surface); border: 1px solid var(--line); border-radius: 8px; padding: 20px; box-shadow: var(--shadow); }
.panel h2 { color: #14233a; }
.narrow { max-width: 680px; }
.hero-panel { display: flex; align-items: center; justify-content: space-between; gap: 18px; margin-bottom: 16px; border-left: 4px solid var(--primary); }
.hero-panel p { margin-bottom: 0; max-width: 720px; }
.login { min-height: 72vh; display: grid; grid-template-columns: minmax(0, 1.15fr) minmax(340px, .85fr); gap: 34px; align-items: center; color: var(--text); }
.login h1 { font-size: 44px; max-width: 680px; letter-spacing: 0; }
.login-copy { padding: 26px 28px; border-radius: 8px; background: rgba(255, 255, 255, .76); border: 1px solid rgba(255, 255, 255, .7); box-shadow: 0 18px 46px rgba(16, 24, 40, .12); }
.login-copy p:not(.eyebrow) { max-width: 640px; color: #44546a; font-size: 17px; }
.login-highlights { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 22px; }
.login-highlights span { display: inline-flex; align-items: center; min-height: 34px; padding: 8px 11px; border: 1px solid #c9d6e4; border-radius: 999px; background: #ffffff; color: #17324d; font-size: 13px; font-weight: 800; }
.login .panel { color: var(--text); border: 0; box-shadow: 0 22px 50px rgba(16, 24, 40, .22); }
.login-panel { padding: 26px; }
.login-panel h2 { font-size: 24px; margin-bottom: 18px; }
.login-primary { width: 100%; text-align: center; padding: 14px 16px; font-size: 16px; margin-bottom: 12px; }
.login-note { display: grid; gap: 6px; margin-top: 18px; padding: 14px; border-radius: 8px; background: #f4f7fb; border: 1px solid var(--line); color: var(--muted); }
.login-note strong { color: var(--text); }
.stack { display: grid; gap: 12px; }
.filters { display: grid; grid-template-columns: max-content minmax(130px, 180px) max-content minmax(220px, 1fr) max-content max-content; gap: 10px; align-items: end; margin-bottom: 16px; }
.toolbar { display: flex; justify-content: flex-end; margin: -4px 0 14px; }
.inline-form { display: inline-block; margin: 0 4px 4px 0; }
label { font-weight: 700; font-size: 14px; }
input, select, textarea { width: 100%; border: 1px solid var(--line-strong); border-radius: 6px; padding: 11px 12px; font: inherit; background: white; color: var(--text); }
input:focus, select:focus, textarea:focus { outline: 3px solid #cde9e5; border-color: var(--primary); }
textarea { min-height: 90px; resize: vertical; }
button, .button { border: 0; background: var(--primary); color: white; border-radius: 6px; padding: 11px 14px; font-weight: 800; cursor: pointer; display: inline-block; box-shadow: 0 1px 2px rgba(16, 24, 40, .12); }
button:hover, .button:hover { background: var(--primary-dark); }
.small { padding: 8px 10px; font-size: 12px; }
.secondary { color: var(--text); background: #e7edf5; }
.secondary:hover { background: #dbe4ef; }
.danger-btn { background: var(--danger); }
.danger-btn:hover { background: #912018; }
.muted { color: var(--muted); margin-top: -4px; }
.metric span { color: var(--muted); font-size: 14px; }
.metric strong { display: block; margin-top: 8px; font-size: 30px; line-height: 1.1; }
.metrics .panel { border-top: 3px solid var(--primary); }
.state { color: var(--primary); font-weight: 800; }
.bars { display: grid; gap: 12px; }
.bar-row { display: grid; grid-template-columns: 140px 1fr 48px; gap: 14px; align-items: center; }
.bar-row span { color: var(--muted); font-weight: 800; }
.bar-row strong { text-align: right; }
.bar { height: 10px; overflow: hidden; background: #edf2f7; border-radius: 999px; }
.bar i { display: block; height: 100%; background: var(--accent); border-radius: inherit; }
.detail { max-width: 820px; }
.detail-head { display: flex; align-items: center; justify-content: space-between; gap: 16px; margin-bottom: 18px; }
.detail dl { display: grid; grid-template-columns: 140px 1fr; gap: 12px 18px; margin: 0 0 20px; }
.detail dt { color: var(--muted); font-weight: 800; }
.detail dd { margin: 0; }
.detail-actions { margin-bottom: 16px; }
.action-panel { border: 1px solid var(--line); border-radius: 8px; padding: 16px; margin: 18px 0; background: var(--surface-soft); }
.action-panel h2 { margin-bottom: 8px; }
.action-panel p { margin-top: 0; color: var(--muted); }
.refund-panel { border-color: #fedf89; background: #fffbeb; }
table { width: 100%; border-collapse: collapse; font-size: 14px; overflow: hidden; }
th, td { padding: 12px 10px; border-bottom: 1px solid var(--line); text-align: left; vertical-align: middle; }
th { color: var(--muted); font-size: 12px; text-transform: uppercase; background: var(--surface-soft); }
tbody tr:hover { background: #f7fbfb; }
.actions { display: flex; gap: 8px; }
.badge { display: inline-block; min-width: 78px; text-align: center; padding: 5px 10px; border-radius: 999px; font-size: 12px; font-weight: 800; background: #eef2f6; }
.badge.approved, .badge.success { color: var(--success); background: #ecfdf3; }
.badge.settled { color: var(--success); background: #dcfae6; }
.badge.pending { color: var(--warning); background: #fffaeb; }
.badge.refundrequested { color: var(--warning); background: #fff4cc; }
.badge.refunded { color: #155eef; background: #eef4ff; }
.badge.cancelled, .badge.rejected, .badge.denied { color: var(--danger); background: #fef3f2; }
.alert { border-radius: 6px; padding: 12px; margin-bottom: 14px; border: 1px solid transparent; }
.alert.danger { background: #fef3f2; color: var(--danger); border-color: #fecdca; }
.alert.success { background: #ecfdf3; color: var(--success); border-color: #abefc6; }
.steps { margin: 0; padding-left: 22px; line-height: 1.9; }
pre { white-space: pre-wrap; background: #111827; color: #e6edf3; padding: 14px; border-radius: 6px; overflow-x: auto; }
.time-cell { font-variant-numeric: tabular-nums; white-space: nowrap; color: #344054; }
.kv-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 12px; }
.kv-item { display: grid; gap: 6px; padding: 14px; border: 1px solid var(--line); border-radius: 8px; background: var(--surface-soft); min-width: 0; }
.kv-item span { color: var(--muted); font-size: 12px; font-weight: 800; text-transform: uppercase; }
.kv-item strong { color: var(--text); font-size: 15px; line-height: 1.45; overflow-wrap: anywhere; }
@media (max-width: 820px) {
  header { height: auto; align-items: flex-start; flex-direction: column; padding: 16px; }
  nav { width: 100%; }
  .userbar { width: 100%; justify-content: space-between; }
  .title { align-items: flex-start; flex-direction: column; }
  .hero-panel { align-items: stretch; flex-direction: column; }
  .filters { grid-template-columns: 1fr; }
  .detail dl { grid-template-columns: 1fr; }
  .login { grid-template-columns: 1fr; }
  .login h1 { font-size: 32px; }
}
"""


def main() -> None:
    load_data()
    server = ThreadingHTTPServer(("0.0.0.0", APP_PORT), FinPayHandler)
    scheme = "http"
    if APP_TLS_ENABLED:
        if not APP_TLS_CERT_FILE or not APP_TLS_KEY_FILE:
            raise RuntimeError("FINPAY_TLS_ENABLED=true requires FINPAY_TLS_CERT_FILE and FINPAY_TLS_KEY_FILE.")
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(certfile=APP_TLS_CERT_FILE, keyfile=APP_TLS_KEY_FILE)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        scheme = "https"
    print(f"FinPay Python app running at {scheme}://0.0.0.0:{APP_PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
