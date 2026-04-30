const accounts = [
  {
    id: "u-customer-1",
    name: "김민준",
    initials: "CU",
    role: "Customer",
    label: "고객",
    mfa: false,
    customerId: "cust-001",
    permissions: ["payment:create", "transaction:read:self"],
  },
  {
    id: "u-merchant-1",
    name: "그린마켓 직원",
    initials: "ME",
    role: "Merchant",
    label: "가맹점",
    mfa: false,
    merchantId: "m-001",
    permissions: ["transaction:read:merchant", "refund:read"],
  },
  {
    id: "u-settlement-1",
    name: "정산 담당자",
    initials: "SO",
    role: "Settlement Operator",
    label: "정산 담당자",
    mfa: true,
    permissions: ["settlement:read", "settlement:update", "transaction:read:settlement"],
  },
  {
    id: "u-ops-1",
    name: "운영 관리자",
    initials: "OP",
    role: "Operations Admin",
    label: "운영자",
    mfa: true,
    permissions: ["transaction:read:limited", "transaction:update:status"],
  },
  {
    id: "u-security-1",
    name: "보안 관리자",
    initials: "SA",
    role: "Security Admin",
    label: "보안 관리자",
    mfa: true,
    permissions: ["iam:policy:manage", "security:rule:manage", "audit:read"],
  },
  {
    id: "u-auditor-1",
    name: "감사 담당자",
    initials: "AU",
    role: "Auditor",
    label: "감사 담당자",
    mfa: true,
    permissions: ["audit:read", "policy:history:read", "report:read"],
  },
];

const merchants = [
  { id: "m-001", name: "그린마켓" },
  { id: "m-002", name: "블루카페" },
  { id: "m-003", name: "테크서점" },
];

let transactions = [
  {
    id: "TX-24001",
    customerId: "cust-001",
    customerName: "김민준",
    merchantId: "m-001",
    amount: 89000,
    status: "Approved",
    settlement: "Pending",
    sensitiveRef: "enc:kms:card-token-71a",
    createdAt: "2026-04-24 09:12",
  },
  {
    id: "TX-24002",
    customerId: "cust-002",
    customerName: "이서연",
    merchantId: "m-002",
    amount: 17500,
    status: "Pending",
    settlement: "Pending",
    sensitiveRef: "enc:kms:card-token-83c",
    createdAt: "2026-04-24 10:04",
  },
  {
    id: "TX-24003",
    customerId: "cust-003",
    customerName: "박지훈",
    merchantId: "m-001",
    amount: 254000,
    status: "Settled",
    settlement: "Settled",
    sensitiveRef: "enc:kms:card-token-16f",
    createdAt: "2026-04-23 17:42",
  },
  {
    id: "TX-24004",
    customerId: "cust-001",
    customerName: "김민준",
    merchantId: "m-003",
    amount: 42000,
    status: "Refunded",
    settlement: "Cancelled",
    sensitiveRef: "enc:kms:card-token-27d",
    createdAt: "2026-04-22 14:20",
  },
];

let auditLogs = [
  logSeed("system", "CloudTrail 수집기 시작", "로그 적재 서비스 역할이 정상 실행되었습니다.", "allowed"),
  logSeed("security", "MFA 정책 활성", "운영/보안/감사 계정에 MFA 필수 정책이 적용되었습니다.", "allowed"),
  logSeed("audit", "정기 점검 보고서 생성", "최근 24시간 접근 이력 요약 보고서가 생성되었습니다.", "allowed"),
];

const permissionDescriptions = {
  "payment:create": "본인 결제 요청 생성",
  "transaction:read:self": "본인 거래만 조회",
  "transaction:read:merchant": "소속 가맹점 거래만 조회",
  "refund:read": "환불 요청 상태 확인",
  "settlement:read": "정산 데이터 조회",
  "settlement:update": "정산 상태 변경",
  "transaction:read:settlement": "정산 목적 거래 조회",
  "transaction:read:limited": "운영 목적 제한 조회",
  "transaction:update:status": "거래 승인/취소/환불 상태 변경",
  "iam:policy:manage": "IAM 및 보안 정책 관리",
  "security:rule:manage": "탐지 규칙 관리",
  "audit:read": "감사 로그 읽기",
  "policy:history:read": "정책 변경 이력 읽기",
  "report:read": "점검 보고서 읽기",
};

const state = {
  activeUser: accounts[0],
  pendingUser: null,
  mfaCode: "",
  toast: "",
  merchantProbe: "m-002",
};

function logSeed(actor, action, detail, result) {
  return {
    id: `audit-${Date.now()}-${Math.random().toString(16).slice(2)}`,
    actor,
    action,
    detail,
    result,
    at: new Date().toLocaleString("ko-KR", { hour12: false }),
  };
}

function addAudit(action, detail, result = "allowed", actor = state.activeUser?.name ?? "system") {
  auditLogs = [logSeed(actor, action, detail, result), ...auditLogs].slice(0, 12);
}

function currency(value) {
  return value.toLocaleString("ko-KR", { style: "currency", currency: "KRW" });
}

function merchantName(id) {
  return merchants.find((merchant) => merchant.id === id)?.name ?? id;
}

function can(permission) {
  return state.activeUser.permissions.includes(permission);
}

function visibleTransactions() {
  const user = state.activeUser;
  if (user.role === "Customer") {
    return transactions.filter((tx) => tx.customerId === user.customerId);
  }
  if (user.role === "Merchant") {
    return transactions.filter((tx) => tx.merchantId === user.merchantId);
  }
  if (user.role === "Security Admin" || user.role === "Auditor") {
    return [];
  }
  return transactions;
}

function login(userId) {
  const user = accounts.find((account) => account.id === userId);
  if (!user) return;

  if (user.mfa) {
    state.pendingUser = user;
    state.mfaCode = "";
    render();
    return;
  }

  state.activeUser = user;
  addAudit("로그인", `${user.label} 계정이 로그인했습니다.`);
  showToast(`${user.name} 계정으로 전환되었습니다.`);
  render();
}

function verifyMfa() {
  if (state.mfaCode !== "123456") {
    addAudit("MFA 실패", `${state.pendingUser.name} 계정의 추가 인증이 실패했습니다.`, "blocked", state.pendingUser.name);
    showToast("MFA 코드가 올바르지 않습니다. 데모 코드는 123456입니다.");
    render();
    return;
  }

  state.activeUser = state.pendingUser;
  addAudit("MFA 로그인", `${state.activeUser.label} 계정이 MFA 인증 후 로그인했습니다.`, "allowed", state.activeUser.name);
  state.pendingUser = null;
  state.mfaCode = "";
  showToast(`${state.activeUser.name} 계정으로 전환되었습니다.`);
  render();
}

function createPayment(event) {
  event.preventDefault();
  if (!can("payment:create")) {
    addAudit("결제 생성 차단", "결제 생성 권한이 없는 계정이 요청했습니다.", "blocked");
    showToast("현재 역할은 결제 요청을 생성할 수 없습니다.");
    render();
    return;
  }

  const form = new FormData(event.currentTarget);
  const amount = Number(form.get("amount"));
  const merchantId = form.get("merchantId");
  const memo = form.get("memo").trim() || "고객 결제 요청";

  if (!amount || amount < 1000) {
    showToast("결제 금액은 1,000원 이상이어야 합니다.");
    return;
  }

  const id = `TX-${Math.floor(24000 + Math.random() * 9000)}`;
  transactions = [
    {
      id,
      customerId: state.activeUser.customerId,
      customerName: state.activeUser.name,
      merchantId,
      amount,
      status: "Pending",
      settlement: "Pending",
      sensitiveRef: `enc:kms:card-token-${Math.random().toString(16).slice(2, 5)}`,
      createdAt: new Date().toLocaleString("ko-KR", {
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
      }),
      memo,
    },
    ...transactions,
  ];

  addAudit("결제 요청 생성", `${id} ${merchantName(merchantId)} ${currency(amount)} 요청이 저장되었습니다.`);
  showToast("결제 요청이 생성되고 민감 참조값은 암호화 토큰으로 저장되었습니다.");
  event.currentTarget.reset();
  render();
}

function updateTransaction(id, nextStatus) {
  if (!can("transaction:update:status") && !can("settlement:update")) {
    addAudit("거래 상태 변경 차단", `${id} 상태 변경 권한이 없습니다.`, "blocked");
    showToast("현재 역할은 거래 상태를 변경할 수 없습니다.");
    render();
    return;
  }

  transactions = transactions.map((tx) => {
    if (tx.id !== id) return tx;
    const settlement = nextStatus === "Settled" ? "Settled" : nextStatus === "Refunded" ? "Cancelled" : tx.settlement;
    return { ...tx, status: nextStatus, settlement };
  });

  addAudit("거래 상태 변경", `${id} 상태가 ${nextStatus}(으)로 변경되었습니다.`);
  showToast(`${id} 상태가 변경되었습니다.`);
  render();
}

function probeMerchantAccess() {
  if (state.activeUser.role !== "Merchant") return;
  const target = state.merchantProbe;
  const allowed = target === state.activeUser.merchantId;
  if (!allowed) {
    addAudit("가맹점 범위 외 조회 차단", `${merchantName(target)} 거래 조회 요청이 거부되었습니다.`, "blocked");
    showToast("다른 가맹점 거래 조회가 차단되었고 감사 로그에 기록되었습니다.");
    render();
    return;
  }
  showToast("소속 가맹점 거래 조회는 허용됩니다.");
}

function showToast(message) {
  state.toast = message;
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => {
    state.toast = "";
    render();
  }, 3200);
}

function renderIcon(name) {
  const paths = {
    plus: '<path d="M12 5v14M5 12h14"/>',
    shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
    lock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
    refresh: '<path d="M21 12a9 9 0 0 1-15.5 6.2"/><path d="M3 12A9 9 0 0 1 18.5 5.8"/><path d="M18 2v4h-4"/><path d="M6 22v-4h4"/>',
    alert: '<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4"/><path d="M12 17h.01"/>',
  };
  return `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths[name]}</svg>`;
}

function render() {
  const app = document.querySelector("#app");
  const txs = visibleTransactions();
  const totalAmount = txs.reduce((sum, tx) => sum + tx.amount, 0);
  const blockedCount = auditLogs.filter((log) => log.result === "blocked").length;

  app.innerHTML = `
    <div class="app-shell">
      <aside class="sidebar">
        <div class="brand">
          <div class="brand-mark">FP</div>
          <div>
            <div class="brand-title">FinPay Console</div>
            <div class="brand-subtitle">RBAC payment control</div>
          </div>
        </div>

        <div class="account-list">
          ${accounts
            .map(
              (account) => `
                <button class="account-button ${account.id === state.activeUser.id ? "active" : ""}" onclick="login('${account.id}')">
                  <span class="avatar">${account.initials}</span>
                  <span>
                    <span class="account-name">${account.name}</span>
                    <span class="account-role">${account.label}</span>
                  </span>
                  ${account.mfa ? '<span class="mfa-dot" title="MFA 필수"></span>' : ""}
                </button>
              `,
            )
            .join("")}
        </div>

        <div class="sidebar-note">
          운영, 보안, 감사, 정산 계정은 MFA가 필요합니다. 데모 인증 코드는 123456입니다.
        </div>
      </aside>

      <main class="main">
        <section class="topbar">
          <div>
            <div class="eyebrow">Fintech payment infrastructure</div>
            <h1>역할 기반 결제 운영 앱</h1>
            <p class="lead">고객 결제 요청, 가맹점 범위 제한, 운영자 상태 변경, 감사 로그 조회를 한 화면에서 확인합니다. 네트워크와 클라우드 구조는 분리하고 애플리케이션 흐름만 구현했습니다.</p>
          </div>
          <div class="session">
            <div class="session-row"><span>현재 계정</span><strong>${state.activeUser.name}</strong></div>
            <div class="session-row"><span>역할</span><strong>${state.activeUser.label}</strong></div>
            <div class="session-row"><span>MFA</span><strong>${state.activeUser.mfa ? "인증됨" : "미대상"}</strong></div>
          </div>
        </section>

        <section class="stats-grid">
          <div class="stat"><div class="stat-label">조회 가능 거래</div><div class="stat-value">${txs.length}</div><div class="stat-trend">RBAC scope applied</div></div>
          <div class="stat"><div class="stat-label">조회 가능 금액</div><div class="stat-value">${currency(totalAmount)}</div><div class="stat-trend">masked by role</div></div>
          <div class="stat"><div class="stat-label">감사 이벤트</div><div class="stat-value">${auditLogs.length}</div><div class="stat-trend">login/access/change</div></div>
          <div class="stat"><div class="stat-label">차단 이벤트</div><div class="stat-value">${blockedCount}</div><div class="stat-trend">policy violation</div></div>
        </section>

        <section class="workspace">
          <div class="panel">
            <div class="panel-header">
              <div>
                <div class="panel-title">거래 워크스페이스</div>
                <div class="panel-subtitle">${workspaceSubtitle()}</div>
              </div>
              <div class="toolbar">
                <button class="icon-button" title="새로고침" onclick="render()">${renderIcon("refresh")}</button>
                ${
                  state.activeUser.role === "Merchant"
                    ? `<select aria-label="가맹점 접근 테스트" onchange="state.merchantProbe=this.value">
                        ${merchants.map((merchant) => `<option value="${merchant.id}" ${merchant.id === state.merchantProbe ? "selected" : ""}>${merchant.name}</option>`).join("")}
                      </select>
                      <button class="ghost-button" onclick="probeMerchantAccess()">${renderIcon("shield")}접근 테스트</button>`
                    : ""
                }
              </div>
            </div>

            ${can("payment:create") ? renderPaymentForm() : ""}
            ${renderTransactions(txs)}
          </div>

          <aside class="right-stack">
            ${renderPermissions()}
            ${renderSecurityPanel()}
            ${renderAuditPanel()}
          </aside>
        </section>
      </main>
    </div>
    ${state.pendingUser ? renderMfaModal() : ""}
    ${state.toast ? `<div class="toast">${state.toast}</div>` : ""}
  `;
}

function workspaceSubtitle() {
  const role = state.activeUser.role;
  if (role === "Customer") return "고객은 본인 거래만 조회하고 새 결제 요청을 만들 수 있습니다.";
  if (role === "Merchant") return "가맹점은 소속 가맹점 거래만 조회할 수 있습니다.";
  if (role === "Auditor") return "감사 담당자는 거래 수정 없이 로그와 정책 이력만 읽습니다.";
  if (role === "Security Admin") return "보안 관리자는 정책과 탐지 상태를 관리하며 거래 처리는 제한됩니다.";
  return "운영/정산 역할은 권한 범위 안에서 거래 상태를 변경할 수 있습니다.";
}

function renderPaymentForm() {
  return `
    <form class="form-grid" onsubmit="createPayment(event)">
      <label>가맹점
        <select name="merchantId">
          ${merchants.map((merchant) => `<option value="${merchant.id}">${merchant.name}</option>`).join("")}
        </select>
      </label>
      <label>결제 금액
        <input name="amount" type="number" min="1000" step="1000" value="12000" />
      </label>
      <label>거래 메모
        <input name="memo" placeholder="주문번호 또는 결제 사유" />
      </label>
      <div class="form-actions">
        <button class="primary-button" type="submit">${renderIcon("plus")}결제 요청</button>
      </div>
    </form>
  `;
}

function renderTransactions(txs) {
  if (!txs.length) {
    return `<div class="empty">현재 역할에서 직접 조회 가능한 거래가 없습니다.</div>`;
  }

  return `
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>거래 ID</th>
            <th>고객</th>
            <th>가맹점</th>
            <th>금액</th>
            <th>상태</th>
            <th>정산</th>
            <th>암호화 참조</th>
            <th>작업</th>
          </tr>
        </thead>
        <tbody>
          ${txs
            .map(
              (tx) => `
                <tr>
                  <td><strong>${tx.id}</strong><div class="audit-meta">${tx.createdAt}</div></td>
                  <td>${tx.customerName}</td>
                  <td>${merchantName(tx.merchantId)}</td>
                  <td class="money">${currency(tx.amount)}</td>
                  <td><span class="badge ${tx.status.toLowerCase()}">${tx.status}</span></td>
                  <td><span class="badge ${tx.settlement.toLowerCase()}">${tx.settlement}</span></td>
                  <td>${tx.sensitiveRef}</td>
                  <td>
                    <div class="toolbar">
                      <button class="ghost-button" onclick="updateTransaction('${tx.id}', 'Approved')" ${can("transaction:update:status") ? "" : "disabled"}>승인</button>
                      <button class="ghost-button" onclick="updateTransaction('${tx.id}', 'Refunded')" ${can("transaction:update:status") ? "" : "disabled"}>환불</button>
                      <button class="ghost-button" onclick="updateTransaction('${tx.id}', 'Settled')" ${can("settlement:update") ? "" : "disabled"}>정산</button>
                    </div>
                  </td>
                </tr>
              `,
            )
            .join("")}
        </tbody>
      </table>
    </div>
  `;
}

function renderPermissions() {
  return `
    <div class="panel">
      <div class="panel-header">
        <div>
          <div class="panel-title">현재 역할 권한</div>
          <div class="panel-subtitle">최소 권한 기준</div>
        </div>
      </div>
      <div class="permission-list">
        ${state.activeUser.permissions
          .map(
            (permission) => `
              <div class="permission-item">
                <div>
                  <div class="permission-name">${permission}</div>
                  <div class="permission-desc">${permissionDescriptions[permission]}</div>
                </div>
                <span class="badge approved">허용</span>
              </div>
            `,
          )
          .join("")}
      </div>
    </div>
  `;
}

function renderSecurityPanel() {
  const policies = [
    ["MFA enforcement", "운영/보안/감사/정산 계정 추가 인증"],
    ["KMS tokenization", "민감 결제 참조값 암호화 저장"],
    ["Scoped queries", "고객/가맹점 거래 조회 범위 제한"],
  ];

  return `
    <div class="panel">
      <div class="panel-header">
        <div>
          <div class="panel-title">보안 정책 상태</div>
          <div class="panel-subtitle">${state.activeUser.role === "Security Admin" ? "관리 가능" : "읽기 전용"}</div>
        </div>
        <button class="icon-button" title="정책 위반 테스트" onclick="addAudit('정책 점검', '민감 기능 접근 정책이 점검되었습니다.'); showToast('정책 점검 이벤트가 기록되었습니다.'); render();">${renderIcon("alert")}</button>
      </div>
      <div class="risk-meter">
        <div class="meter-row"><span>인증</span><div class="meter-track"><div class="meter-fill" style="width: 92%"></div></div><strong>92%</strong></div>
        <div class="meter-row"><span>접근통제</span><div class="meter-track"><div class="meter-fill" style="width: 88%"></div></div><strong>88%</strong></div>
        <div class="meter-row"><span>감사추적</span><div class="meter-track"><div class="meter-fill" style="width: 96%"></div></div><strong>96%</strong></div>
      </div>
      <div class="policy-list">
        ${policies
          .map(
            ([name, desc]) => `
              <div class="policy-item">
                <div class="permission-name">${name}</div>
                <div class="policy-desc">${desc}</div>
              </div>
            `,
          )
          .join("")}
      </div>
    </div>
  `;
}

function renderAuditPanel() {
  const canReadAudit = can("audit:read") || ["Operations Admin", "Settlement Operator"].includes(state.activeUser.role);
  return `
    <div class="panel">
      <div class="panel-header">
        <div>
          <div class="panel-title">감사 로그</div>
          <div class="panel-subtitle">로그인, 차단, 상태 변경 이력</div>
        </div>
        <span class="badge">${canReadAudit ? "조회 가능" : "요약"}</span>
      </div>
      <div class="audit-list">
        ${auditLogs
          .slice(0, canReadAudit ? 8 : 4)
          .map(
            (log) => `
              <div class="audit-item ${log.result === "blocked" ? "blocked" : ""}">
                <div class="audit-action">${log.action}</div>
                <div class="audit-meta">${log.actor} · ${log.at} · ${log.result}</div>
                <div class="audit-meta">${log.detail}</div>
              </div>
            `,
          )
          .join("")}
      </div>
    </div>
  `;
}

function renderMfaModal() {
  return `
    <div class="modal-backdrop" role="dialog" aria-modal="true">
      <div class="modal">
        <h2>${renderIcon("lock")} MFA 추가 인증</h2>
        <p>${state.pendingUser.name} 계정은 민감 권한을 포함하므로 추가 인증이 필요합니다.</p>
        <label>인증 코드
          <input value="${state.mfaCode}" oninput="state.mfaCode=this.value" placeholder="123456" inputmode="numeric" autofocus />
        </label>
        <div class="modal-actions">
          <button class="ghost-button" onclick="state.pendingUser=null; render()">취소</button>
          <button class="primary-button" onclick="verifyMfa()">${renderIcon("shield")}인증</button>
        </div>
      </div>
    </div>
  `;
}

render();
