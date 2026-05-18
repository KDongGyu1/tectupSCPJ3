from __future__ import annotations

import html
import csv
import io
import json
import os
import re
import socket
import time
import uuid
from datetime import datetime, timezone
from http import HTTPStatus
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


APP_PORT = int(os.environ.get("FINPAY_PORT", "8088"))
APP_ROOT = Path(__file__).resolve().parent
DATA_PATH = APP_ROOT / "data" / "finpay-data.json"

APP_CONFIG = {
    "environment": os.environ.get("FINPAY_ENV", "local"),
    "aws_region": os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION", "ap-northeast-2"),
    "storage": os.environ.get("FINPAY_STORAGE", "local"),
    "cognito_user_pool_id": os.environ.get("COGNITO_USER_POOL_ID", ""),
    "cognito_web_client_id": os.environ.get("COGNITO_WEB_CLIENT_ID", ""),
    "database_url": os.environ.get("DATABASE_URL", ""),
    "rds_endpoint": os.environ.get("RDS_ENDPOINT", ""),
    "rds_master_secret_arn": os.environ.get("RDS_MASTER_SECRET_ARN", ""),
    "db_name": os.environ.get("DB_NAME", "finpay"),
    "db_user": os.environ.get("DB_USER", ""),
    "db_password": os.environ.get("DB_PASSWORD", ""),
    "cloudwatch_log_group": os.environ.get("CLOUDWATCH_LOG_GROUP", ""),
    "cloudwatch_log_stream": os.environ.get("CLOUDWATCH_LOG_STREAM", ""),
}

STORAGE_WARNING = ""
CLOUDWATCH_SEQUENCE_TOKEN = None
CLOUDWATCH_READY = False
CLOUDWATCH_WARNING = ""

USERS = {
    "customer@finpay.local": {"name": "고객 사용자", "role": "Customer"},
    "merchant@finpay.local": {"name": "가맹점 사용자", "role": "Merchant"},
    "settlement@finpay.local": {"name": "정산 담당자", "role": "SettlementOperator"},
    "auditor@finpay.local": {"name": "감사 담당자", "role": "Auditor"},
    "ops@finpay.local": {"name": "운영 관리자", "role": "OperationsAdmin"},
    "security@finpay.local": {"name": "보안 관리자", "role": "SecurityAdmin"},
}

NAV_ITEMS = [
    ("대시보드", "/dashboard", {"Customer", "Merchant", "SettlementOperator", "Auditor", "OperationsAdmin", "SecurityAdmin"}),
    ("내 권한", "/my-access", {"Customer", "Merchant", "SettlementOperator", "Auditor", "OperationsAdmin", "SecurityAdmin"}),
    ("결제 생성", "/payments/new", {"Customer", "Merchant"}),
    ("결제 승인", "/payments/review", {"SettlementOperator", "OperationsAdmin"}),
    ("결제 내역", "/payments", {"Customer", "Merchant", "SettlementOperator", "Auditor", "OperationsAdmin"}),
    ("감사 이벤트", "/audit/events", {"Auditor", "SecurityAdmin", "OperationsAdmin"}),
    ("보안 상태", "/security/status", {"SecurityAdmin", "OperationsAdmin"}),
    ("시스템 상태", "/system/status", {"OperationsAdmin", "SecurityAdmin"}),
]

ROLE_DESCRIPTIONS = {
    "Customer": "결제 요청을 생성하고 본인이 요청한 결제 내역을 조회합니다.",
    "Merchant": "가맹점 결제 요청을 생성하고 본인 관련 결제 내역을 조회합니다.",
    "SettlementOperator": "승인 대기 결제를 검토하고 승인 또는 거절합니다.",
    "Auditor": "결제 내역과 감사 이벤트를 조회합니다.",
    "OperationsAdmin": "결제 운영, 감사 조회, 시스템 상태를 관리합니다.",
    "SecurityAdmin": "보안 상태와 감사 이벤트를 확인하고 차단 이벤트를 기록합니다.",
}

SESSIONS: dict[str, str] = {}


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def esc(value: object) -> str:
    return html.escape(str(value), quote=True)


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
    }


def load_data() -> dict:
    if APP_CONFIG["storage"] == "postgres":
        try:
            return postgres_load_data()
        except Exception as exc:
            set_storage_warning(f"PostgreSQL load failed: {exc}")

    if not DATA_PATH.exists():
        DATA_PATH.parent.mkdir(parents=True, exist_ok=True)
        seed = seed_data()
        save_data(seed)
        return seed

    with DATA_PATH.open("r", encoding="utf-8") as fp:
        return json.load(fp)


def save_data(data: dict) -> None:
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

    return f"host={host} port={port} dbname={dbname} user={user} password={password} connect_timeout=3"


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

    if not payments and not audit_events:
        seed = seed_data()
        postgres_save_data(seed)
        return seed
    return {"payments": payments, "audit_events": audit_events}


def postgres_save_data(data: dict) -> None:
    ensure_postgres_schema()
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


def visible_payments(data: dict, user: dict) -> list[dict]:
    if user["role"] in {"Customer", "Merchant"}:
        return [p for p in data["payments"] if p["created_by"] == user["email"]]
    if user["role"] in {"SettlementOperator", "Auditor", "OperationsAdmin"}:
        return list(data["payments"])
    return []


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
    return {
        "Pending": sum(1 for p in payments if p["status"] == "Pending"),
        "Approved": sum(1 for p in payments if p["status"] == "Approved"),
        "Rejected": sum(1 for p in payments if p["status"] == "Rejected"),
    }


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
            "user_pool_id": APP_CONFIG["cognito_user_pool_id"],
            "web_client_id": APP_CONFIG["cognito_web_client_id"],
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
    server_version = "FinPayPython/0.1"

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/api/health":
            self.send_json({"status": "healthy", "runtime": "python", "version": "0.1.0"})
            return

        if path == "/api/db-check":
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
            if user["role"] not in {"OperationsAdmin", "SecurityAdmin"}:
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
            if user["role"] not in {"Auditor", "SecurityAdmin", "OperationsAdmin"}:
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
            if user["role"] not in {"Auditor", "SecurityAdmin", "OperationsAdmin"}:
                add_event(user["email"], user["role"], "EXPORT_AUDIT_EVENTS", "Denied", "감사 이벤트 내보내기 권한 없음")
                self.send_html(self.forbidden_page(user, {"Auditor", "SecurityAdmin", "OperationsAdmin"}), HTTPStatus.FORBIDDEN)
                return
            rows = load_data()["audit_events"]
            add_event(user["email"], user["role"], "EXPORT_AUDIT_EVENTS", "Success", "감사 이벤트 CSV 내보내기")
            self.send_csv("finpay-audit-events.csv", to_csv(rows, ["id", "time", "actor", "role", "action", "result", "detail"]))
            return

        routes = {
            "/dashboard": (self.dashboard_page, {"Customer", "Merchant", "SettlementOperator", "Auditor", "OperationsAdmin", "SecurityAdmin"}),
            "/my-access": (self.my_access_page, {"Customer", "Merchant", "SettlementOperator", "Auditor", "OperationsAdmin", "SecurityAdmin"}),
            "/payments/new": (self.new_payment_page, {"Customer", "Merchant"}),
            "/payments/review": (self.review_payments_page, {"SettlementOperator", "OperationsAdmin"}),
            "/payments": (self.payment_history_page, {"Customer", "Merchant", "SettlementOperator", "Auditor", "OperationsAdmin"}),
            "/detail": (self.payment_detail_from_query_page, {"Customer", "Merchant", "SettlementOperator", "Auditor", "OperationsAdmin"}),
            "/audit/events": (self.audit_events_page, {"Auditor", "SecurityAdmin", "OperationsAdmin"}),
            "/security/status": (self.security_status_page, {"SecurityAdmin", "OperationsAdmin"}),
            "/system/status": (self.system_status_page, {"OperationsAdmin", "SecurityAdmin"}),
        }

        if path not in routes:
            self.send_error_page(HTTPStatus.NOT_FOUND, "페이지를 찾을 수 없습니다.")
            return

        page, allowed_roles = routes[path]
        if user["role"] not in allowed_roles:
            add_event(user["email"], user["role"], f"GET {path}", "Denied", "권한 없는 화면 접근")
            self.send_html(self.forbidden_page(user, allowed_roles), HTTPStatus.FORBIDDEN)
            return

        self.send_html(page(user))

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        form = self.read_form()

        if path == "/auth/login":
            email = form.get("email", [""])[0]
            if email not in USERS:
                self.send_html(self.login_page("등록되지 않은 계정입니다."), HTTPStatus.BAD_REQUEST)
                return
            sid = uuid.uuid4().hex
            SESSIONS[sid] = email
            role = USERS[email]["role"]
            add_event(email, role, "LOGIN", "Success", "데모 계정 로그인")
            self.send_response(HTTPStatus.SEE_OTHER)
            self.send_header("Location", "/dashboard")
            self.send_header("Set-Cookie", f"finpay_session={sid}; HttpOnly; SameSite=Lax; Path=/")
            self.end_headers()
            return

        if path == "/auth/logout":
            user = self.current_user()
            if user:
                add_event(user["email"], user["role"], "LOGOUT", "Success", "로그아웃")
            self.send_response(HTTPStatus.SEE_OTHER)
            self.send_header("Location", "/login")
            self.send_header("Set-Cookie", "finpay_session=; Max-Age=0; Path=/")
            self.end_headers()
            return

        user = self.require_login()
        if not user:
            return

        if path == "/payments":
            self.create_payment(user, form)
            return

        approve_match = re.fullmatch(r"/payments/([^/]+)/approve", path)
        reject_match = re.fullmatch(r"/payments/([^/]+)/reject", path)
        if approve_match:
            self.update_payment_status(user, approve_match.group(1), "Approved")
            return
        if reject_match:
            self.update_payment_status(user, reject_match.group(1), "Rejected")
            return

        if path == "/security/test-denied-access":
            add_event(user["email"], user["role"], "DENIED_ACCESS_SIMULATION", "Denied", "권한 차단 이벤트 생성")
            self.redirect("/security/status?tested=1")
            return

        self.send_error_page(HTTPStatus.NOT_FOUND, "요청 경로를 찾을 수 없습니다.")

    def create_payment(self, user: dict, form: dict[str, list[str]]) -> None:
        if user["role"] not in {"Customer", "Merchant"}:
            add_event(user["email"], user["role"], "CREATE_PAYMENT", "Denied", "결제 생성 권한 없음")
            self.send_html(self.forbidden_page(user, {"Customer", "Merchant"}), HTTPStatus.FORBIDDEN)
            return

        merchant = form.get("merchant", [""])[0].strip()
        amount_text = form.get("amount", ["0"])[0].strip()
        memo = form.get("memo", [""])[0].strip()
        try:
            amount = int(amount_text)
        except ValueError:
            amount = 0

        if not merchant or amount <= 0:
            self.send_html(self.new_payment_page(user, "가맹점명과 1원 이상의 금액을 입력해야 합니다."), HTTPStatus.BAD_REQUEST)
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
        if user["role"] not in {"SettlementOperator", "OperationsAdmin"}:
            add_event(user["email"], user["role"], f"{status.upper()}_PAYMENT", "Denied", "결제 승인 권한 없음")
            self.send_html(self.forbidden_page(user, {"SettlementOperator", "OperationsAdmin"}), HTTPStatus.FORBIDDEN)
            return

        data = load_data()
        for payment in data["payments"]:
            if payment["id"] == payment_id:
                payment["status"] = status
                payment["reviewed_by"] = user["email"]
                payment["reviewed_at"] = now_iso()
                save_data(data)
                add_event(user["email"], user["role"], f"{status.upper()}_PAYMENT", "Success", f"{payment_id} 처리")
                message = "approved" if status == "Approved" else "rejected"
                self.redirect(f"/payments/review?msg={message}")
                return
        self.send_error_page(HTTPStatus.NOT_FOUND, "결제 건을 찾을 수 없습니다.")

    def login_page(self, error: str = "") -> str:
        options = "".join(
            f'<option value="{esc(email)}">{esc(info["role"])} - {esc(info["name"])}</option>'
            for email, info in USERS.items()
        )
        message = f'<div class="alert danger">{esc(error)}</div>' if error else ""
        return self.page(
            "로그인",
            None,
            f"""
            <section class="login">
              <div>
                <p class="eyebrow">FinPay Application</p>
                <h1>역할 기반 결제 관리</h1>
                <p>고객 결제 요청부터 정산 승인, 감사 이벤트 확인까지 FinPay 운영 흐름을 제공합니다.</p>
              </div>
              <form method="post" action="/auth/login" class="panel">
                <h2>계정 선택</h2>
                {message}
                <label>계정</label>
                <select name="email">{options}</select>
                <button type="submit">로그인</button>
              </form>
            </section>
            """,
        )

    def dashboard_page(self, user: dict) -> str:
        data = load_data()
        payments = visible_payments(data, user)
        payment_counts = count_by_status(payments)
        pending = payment_counts["Pending"]
        approved = payment_counts["Approved"]
        denied = sum(1 for e in data["audit_events"] if e["result"] == "Denied")
        total_amount = sum(p["amount"] for p in payments)
        recent_rows = "".join(self.payment_row(p) for p in payments[:5]) or '<tr><td colspan="6">표시할 결제가 없습니다.</td></tr>'
        primary_link = '<a class="button" href="/payments/new">결제 생성</a>' if user["role"] in {"Customer", "Merchant"} else '<a class="button" href="/payments">결제 내역</a>'
        return self.page(
            "대시보드",
            user,
            f"""
            <div class="grid metrics">
              {self.metric("표시 결제", len(payments))}
              {self.metric("승인 대기", pending)}
              {self.metric("승인 완료", approved)}
              {self.metric("총 결제 금액", format_money(total_amount))}
            </div>
            <section class="panel hero-panel">
              <div>
                <h2>오늘의 운영 현황</h2>
                <p>현재 역할에서 확인 가능한 결제 요청, 승인 상태, 감사 이벤트를 기준으로 서비스 상태를 확인합니다.</p>
              </div>
              {primary_link}
            </section>
            <section class="grid">
              {self.status_card("결제 업무", "운영 중", "고객과 가맹점은 결제 요청을 생성하고 정산 담당자는 승인 또는 거절합니다.")}
              {self.status_card("접근 제어", "역할 기반", "사용자 역할에 따라 메뉴와 화면 접근 권한이 분리됩니다.")}
              {self.status_card("감사 추적", f"{denied}건 차단", "로그인, 결제 처리, 차단 이벤트가 감사 이벤트로 기록됩니다.")}
            </section>
            <section class="panel">
              <h2>결제 상태 분포</h2>
              {self.distribution(payment_counts)}
            </section>
            <section class="panel">
              <h2>최근 결제</h2>
              <table>
                <thead><tr><th>ID</th><th>상태</th><th>가맹점</th><th>금액</th><th>생성자</th><th>상세</th></tr></thead>
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
              {self.status_card("사용자", user["name"], user["email"])}
              {self.status_card("역할", user["role"], ROLE_DESCRIPTIONS[user["role"]])}
              {self.status_card("접근 정책", "역할 기반", "메뉴와 주요 API는 현재 역할에 따라 허용됩니다.")}
            </section>
            <section class="panel">
              <h2>허용된 메뉴</h2>
              <table>
                <thead><tr><th>기능</th><th>경로</th></tr></thead>
                <tbody>{allowed_rows}</tbody>
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
        return self.page(
            "결제 생성",
            user,
            f"""
            <section class="panel narrow">
              <h2>새 결제 요청</h2>
              {message}
              <form method="post" action="/payments" class="stack">
                <label>가맹점명</label>
                <input name="merchant" value="FinPay Store" required>
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
            f'<option value="{esc(value)}" {"selected" if selected_status == value else ""}>{esc(value)}</option>'
            for value in ["All", "Pending", "Approved", "Rejected"]
        )
        rows = "".join(self.payment_row(p) for p in payments) or '<tr><td colspan="6">표시할 결제가 없습니다.</td></tr>'
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
                <thead><tr><th>ID</th><th>상태</th><th>가맹점</th><th>금액</th><th>생성자</th><th>상세</th></tr></thead>
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
        if payment["status"] == "Pending" and user["role"] in {"SettlementOperator", "OperationsAdmin"}:
            review = f"""
            <div class="actions detail-actions">
              <form method="post" action="/payments/{esc(payment["id"])}/approve"><button type="submit">승인</button></form>
              <form method="post" action="/payments/{esc(payment["id"])}/reject"><button type="submit" class="danger-btn">거절</button></form>
            </div>
            """

        timeline = "".join(
            f"""
            <tr>
              <td>{esc(event["time"])}</td>
              <td>{esc(event["actor"])}</td>
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
                <span class="badge {esc(payment["status"].lower())}">{esc(payment["status"])}</span>
              </div>
              <dl>
                <dt>가맹점</dt><dd>{esc(payment["merchant"])}</dd>
                <dt>금액</dt><dd>{esc(format_money(payment["amount"]))}</dd>
                <dt>생성자</dt><dd>{esc(payment["created_by"])}</dd>
                <dt>생성 시간</dt><dd>{esc(payment["created_at"])}</dd>
                <dt>메모</dt><dd>{esc(payment.get("memo", ""))}</dd>
                <dt>처리자</dt><dd>{esc(payment.get("reviewed_by", "-"))}</dd>
                <dt>처리 시간</dt><dd>{esc(payment.get("reviewed_at", "-"))}</dd>
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
              <td>{esc(e["time"])}</td>
              <td>{esc(e["actor"])}</td>
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

    def security_status_page(self, user: dict) -> str:
        tested = "tested=1" in self.path
        message = '<div class="alert success">권한 차단 이벤트가 감사 로그에 기록되었습니다.</div>' if tested else ""
        status = integration_status()
        cognito_state = "설정됨" if status["cognito"]["configured"] else "미설정"
        cloudwatch_state = "설정됨" if status["cloudwatch"]["configured"] else "미설정"
        return self.page(
            "보안 상태",
            user,
            f"""
            <div class="grid">
              {self.status_card("Cognito", cognito_state, "User Pool과 Web Client 설정 상태를 확인합니다.")}
              {self.status_card("IAM 권한", "역할 기반", "역할별 화면 접근 권한이 분리되어 있습니다.")}
              {self.status_card("CloudWatch", cloudwatch_state, "구조화 로그 전송 대상 설정 상태를 확인합니다.")}
            </div>
            <section class="panel narrow">
              <h2>권한 차단 이벤트 생성</h2>
              {message}
              <p>보안 운영자가 접근 차단 이벤트를 수동으로 기록할 수 있습니다.</p>
              <form method="post" action="/security/test-denied-access">
                <button type="submit">차단 이벤트 기록</button>
              </form>
            </section>
            """,
        )

    def system_status_page(self, user: dict) -> str:
        status = integration_status()
        rds = status["rds"]
        secret_state = "설정됨" if status["secrets_manager"]["configured"] else "미설정"
        return self.page(
            "시스템 상태",
            user,
            f"""
            <div class="grid">
              {self.status_card("앱 런타임", "Python", "표준 라이브러리 기반 로컬 앱")}
              {self.status_card("저장 모드", status["storage"]["mode"], status["storage"]["warning"] or "정상")}
              {self.status_card("저장소", rds["status"], f'{esc(rds.get("host", "Local JSON"))}')}
              {self.status_card("Secrets Manager", secret_state, status["secrets_manager"]["secret_arn"] or "RDS Secret ARN 미설정")}
              {self.status_card("API", "정상", "/api/health, /api/db-check 제공")}
            </div>
            <section class="panel">
              <h2>API 확인</h2>
              <pre>GET http://127.0.0.1:{APP_PORT}/api/health
GET http://127.0.0.1:{APP_PORT}/api/db-check
GET http://127.0.0.1:{APP_PORT}/api/config
GET http://127.0.0.1:{APP_PORT}/api/me
GET http://127.0.0.1:{APP_PORT}/api/payments
GET http://127.0.0.1:{APP_PORT}/api/audit-events</pre>
            </section>
            <section class="panel">
              <h2>AWS 연동 설정</h2>
              <dl>
                <dt>Environment</dt><dd>{esc(status["environment"])}</dd>
                <dt>AWS Region</dt><dd>{esc(status["aws_region"])}</dd>
                <dt>Storage Mode</dt><dd>{esc(status["storage"]["mode"])}</dd>
                <dt>Cognito User Pool</dt><dd>{esc(status["cognito"]["user_pool_id"] or "-")}</dd>
                <dt>Cognito Web Client</dt><dd>{esc(status["cognito"]["web_client_id"] or "-")}</dd>
                <dt>RDS Endpoint</dt><dd>{esc(rds.get("host", "-"))}</dd>
                <dt>RDS Port</dt><dd>{esc(rds.get("port", "-"))}</dd>
                <dt>RDS Latency</dt><dd>{esc(str(rds.get("latency_ms", "-")) + (" ms" if "latency_ms" in rds else ""))}</dd>
                <dt>CloudWatch Log Group</dt><dd>{esc(status["cloudwatch"]["log_group"] or "-")}</dd>
              </dl>
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
            links = "".join(
                f'<a href="{path}">{label}</a>'
                for label, path in allowed_nav_items(user)
            )
            nav = f"<nav>{links}</nav>"
            userbar = f"""
            <form method="post" action="/auth/logout" class="userbar">
              <span>{esc(user["name"])} · {esc(user["role"])}</span>
              <button type="submit" class="small">로그아웃</button>
            </form>
            """

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
    <div class="title"><p class="eyebrow">Python Prototype</p><h1>{esc(title)}</h1></div>
    {body}
  </main>
</body>
</html>"""

    def payment_row(self, p: dict) -> str:
        return f"""
        <tr>
          <td>{esc(p["id"])}</td>
          <td><span class="badge {esc(p["status"].lower())}">{esc(p["status"])}</span></td>
          <td>{esc(p["merchant"])}</td>
          <td>{esc(format_money(p["amount"]))}</td>
          <td>{esc(p["created_by"])}</td>
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

    def metric(self, label: str, value: int) -> str:
        return f'<article class="panel metric"><span>{esc(label)}</span><strong>{esc(value)}</strong></article>'

    def status_card(self, title: str, state: str, detail: str) -> str:
        return f'<article class="panel"><h2>{esc(title)}</h2><p class="state">{esc(state)}</p><p>{esc(detail)}</p></article>'

    def distribution(self, counts: dict[str, int]) -> str:
        total = sum(counts.values())
        if total == 0:
            return '<p class="muted">표시할 데이터가 없습니다.</p>'
        rows = ""
        for label, count in counts.items():
            percent = round((count / total) * 100)
            rows += f"""
            <div class="bar-row">
              <span>{esc(label)}</span>
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
        email = SESSIONS.get(morsel.value)
        if not email or email not in USERS:
            return None
        return {"email": email, **USERS[email]}

    def require_login(self) -> dict | None:
        user = self.current_user()
        if not user:
            self.redirect("/login")
            return None
        return user

    def read_form(self) -> dict[str, list[str]]:
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length).decode("utf-8")
        return parse_qs(raw)

    def send_html(self, body: str, status: HTTPStatus = HTTPStatus.OK) -> None:
        payload = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def send_json(self, body: dict, status: HTTPStatus = HTTPStatus.OK) -> None:
        payload = json.dumps(body, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def send_csv(self, filename: str, content: str) -> None:
        payload = content.encode("utf-8-sig")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/csv; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
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
        self.end_headers()

    def log_message(self, format: str, *args: object) -> None:
        return


STYLE = """
:root {
  color-scheme: light;
  --bg: #f5f7fb;
  --surface: #ffffff;
  --line: #d9e0ea;
  --text: #172033;
  --muted: #667085;
  --primary: #0f766e;
  --primary-dark: #115e59;
  --danger: #b42318;
  --warning: #b54708;
  --success: #027a48;
}
* { box-sizing: border-box; }
body { margin: 0; font-family: Arial, "Malgun Gothic", sans-serif; background: var(--bg); color: var(--text); }
header { height: 64px; display: flex; align-items: center; gap: 18px; padding: 0 28px; background: var(--surface); border-bottom: 1px solid var(--line); position: sticky; top: 0; z-index: 10; }
.brand { font-weight: 800; font-size: 22px; color: var(--primary); text-decoration: none; }
nav { display: flex; gap: 6px; flex-wrap: wrap; flex: 1; }
nav a, .button { color: var(--text); text-decoration: none; padding: 9px 11px; border-radius: 6px; font-size: 14px; }
nav a:hover, .button:hover { background: #eef7f5; }
.userbar { display: flex; gap: 10px; align-items: center; color: var(--muted); font-size: 13px; }
main { max-width: 1180px; margin: 0 auto; padding: 32px 22px 56px; }
.title { margin-bottom: 18px; }
.eyebrow { margin: 0 0 6px; color: var(--primary); text-transform: uppercase; letter-spacing: .04em; font-size: 12px; font-weight: 700; }
h1 { margin: 0; font-size: 30px; }
h2 { margin: 0 0 14px; font-size: 18px; }
p { line-height: 1.6; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 14px; margin-bottom: 16px; }
.panel { background: var(--surface); border: 1px solid var(--line); border-radius: 8px; padding: 20px; box-shadow: 0 1px 2px rgba(16, 24, 40, .04); }
.narrow { max-width: 680px; }
.hero-panel { display: flex; align-items: center; justify-content: space-between; gap: 18px; margin-bottom: 16px; }
.hero-panel p { margin-bottom: 0; max-width: 720px; }
.login { min-height: 74vh; display: grid; grid-template-columns: 1.2fr .8fr; gap: 32px; align-items: center; }
.login h1 { font-size: 42px; }
.stack { display: grid; gap: 10px; }
.filters { display: grid; grid-template-columns: max-content minmax(130px, 180px) max-content minmax(220px, 1fr) max-content max-content; gap: 10px; align-items: end; margin-bottom: 16px; }
.toolbar { display: flex; justify-content: flex-end; margin: -4px 0 14px; }
label { font-weight: 700; font-size: 14px; }
input, select, textarea { width: 100%; border: 1px solid var(--line); border-radius: 6px; padding: 11px 12px; font: inherit; background: white; }
textarea { min-height: 90px; resize: vertical; }
button, .button { border: 0; background: var(--primary); color: white; border-radius: 6px; padding: 11px 14px; font-weight: 700; cursor: pointer; display: inline-block; }
button:hover { background: var(--primary-dark); }
.small { padding: 8px 10px; font-size: 12px; }
.secondary { color: var(--text); background: #e8edf4; }
.danger-btn { background: var(--danger); }
.muted { color: var(--muted); margin-top: -4px; }
.metric span { color: var(--muted); font-size: 14px; }
.metric strong { display: block; margin-top: 8px; font-size: 30px; }
.state { color: var(--primary); font-weight: 800; }
.bars { display: grid; gap: 12px; }
.bar-row { display: grid; grid-template-columns: 110px 1fr 48px; gap: 12px; align-items: center; }
.bar-row span { color: var(--muted); font-weight: 800; }
.bar-row strong { text-align: right; }
.bar { height: 10px; overflow: hidden; background: #edf2f7; border-radius: 999px; }
.bar i { display: block; height: 100%; background: var(--primary); border-radius: inherit; }
.detail { max-width: 820px; }
.detail-head { display: flex; align-items: center; justify-content: space-between; gap: 16px; margin-bottom: 18px; }
.detail dl { display: grid; grid-template-columns: 140px 1fr; gap: 12px 18px; margin: 0 0 20px; }
.detail dt { color: var(--muted); font-weight: 800; }
.detail dd { margin: 0; }
.detail-actions { margin-bottom: 16px; }
table { width: 100%; border-collapse: collapse; font-size: 14px; }
th, td { padding: 12px 10px; border-bottom: 1px solid var(--line); text-align: left; vertical-align: middle; }
th { color: var(--muted); font-size: 12px; text-transform: uppercase; }
.actions { display: flex; gap: 8px; }
.badge { display: inline-block; padding: 5px 8px; border-radius: 999px; font-size: 12px; font-weight: 800; background: #eef2f6; }
.badge.approved, .badge.success { color: var(--success); background: #ecfdf3; }
.badge.pending { color: var(--warning); background: #fffaeb; }
.badge.rejected, .badge.denied { color: var(--danger); background: #fef3f2; }
.alert { border-radius: 6px; padding: 12px; margin-bottom: 14px; }
.alert.danger { background: #fef3f2; color: var(--danger); }
.alert.success { background: #ecfdf3; color: var(--success); }
.steps { margin: 0; padding-left: 22px; line-height: 1.9; }
pre { white-space: pre-wrap; background: #101828; color: #e6edf3; padding: 14px; border-radius: 6px; }
@media (max-width: 820px) {
  header { height: auto; align-items: flex-start; flex-direction: column; padding: 16px; }
  nav { width: 100%; }
  .userbar { width: 100%; justify-content: space-between; }
  .hero-panel { align-items: stretch; flex-direction: column; }
  .filters { grid-template-columns: 1fr; }
  .detail dl { grid-template-columns: 1fr; }
  .login { grid-template-columns: 1fr; }
  .login h1 { font-size: 32px; }
}
"""


def main() -> None:
    load_data()
    server = ThreadingHTTPServer(("127.0.0.1", APP_PORT), FinPayHandler)
    print(f"FinPay Python app running at http://127.0.0.1:{APP_PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
