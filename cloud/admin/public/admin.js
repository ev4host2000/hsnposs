const API_BASE = '/v1/admin';
const TOKEN_KEY = 'miza_ops_token';

const loginView = document.getElementById('login-view');
const mainView = document.getElementById('main-view');
const loginForm = document.getElementById('login-form');
const loginError = document.getElementById('login-error');
const adminEmailEl = document.getElementById('admin-email');
const companiesTbody = document.getElementById('companies-tbody');
const devicesTbody = document.getElementById('devices-tbody');
const companySummary = document.getElementById('company-summary');
const createPlan = document.getElementById('create-plan');
const createForm = document.getElementById('create-form');
const createError = document.getElementById('create-error');
const createResult = document.getElementById('create-result');
const createResultWrap = document.getElementById('create-result-wrap');
const copyWelcomeBtn = document.getElementById('copy-welcome');
const companySearch = document.getElementById('company-search');
const syncOverviewCards = document.getElementById('sync-overview-cards');
const staleDevicesTbody = document.getElementById('stale-devices-tbody');
const syncFailuresTbody = document.getElementById('sync-failures-tbody');
const syncConflictsTbody = document.getElementById('sync-conflicts-tbody');
const companySyncHealth = document.getElementById('company-sync-health');
const obsStatusBanner = document.getElementById('obs-status-banner');
const obsMetricsCards = document.getElementById('obs-metrics-cards');
const obsAlerts = document.getElementById('obs-alerts');
const obsInfra = document.getElementById('obs-infra');
const auditTbody = document.getElementById('audit-tbody');
const auditMeta = document.getElementById('audit-meta');
const dashStatusLine = document.getElementById('dash-status-line');
const dashStatusPill = document.getElementById('dash-status-pill');
const dashMailHint = document.getElementById('dash-mail-hint');
const dashMetricsCards = document.getElementById('dash-metrics-cards');
const dashAlerts = document.getElementById('dash-alerts');
const dashSignupsTbody = document.getElementById('dash-signups-tbody');
const dashVouchersTbody = document.getElementById('dash-vouchers-tbody');
const dashQuickSummary = document.getElementById('dash-quick-summary');
const dashPendingBadge = document.getElementById('dash-pending-badge');
const dashHealthCards = document.getElementById('dash-health-cards');
const signupResult = document.getElementById('signup-result');
const signupResultWrap = document.getElementById('signup-result-wrap');
const copySignupWelcomeBtn = document.getElementById('copy-signup-welcome');
const modal = document.getElementById('modal');
const modalTitle = document.getElementById('modal-title');
const modalBody = document.getElementById('modal-body');
const modalActions = document.getElementById('modal-actions');
const toast = document.getElementById('toast');

let selectedCompanyId = null;
let selectedCompany = null;
let plansCache = [];
let lastWelcomeCard = '';
let searchTimer = null;
let companiesCache = [];
let companiesStatusFilter = 'all';
let toastTimer = null;
let modalReturnFocus = null;
let viewLoadToken = 0;
let monRefreshTimer = null;
let monLatest = null;

function getToken() {
  return localStorage.getItem(TOKEN_KEY);
}

function setToken(token) {
  if (token) localStorage.setItem(TOKEN_KEY, token);
  else localStorage.removeItem(TOKEN_KEY);
}

function showToast(message, type = 'info') {
  if (!toast) return;
  clearTimeout(toastTimer);
  toast.textContent = message;
  toast.className = `toast toast-${type}`;
  toast.classList.remove('hidden');
  toastTimer = setTimeout(() => toast.classList.add('hidden'), 3200);
}

function setButtonBusy(button, busy) {
  if (!button) return;
  button.classList.toggle('is-busy', busy);
  button.setAttribute('aria-busy', busy ? 'true' : 'false');
  button.disabled = !!busy;
}

function setViewLoading(busy) {
  const main = document.querySelector('.main-area');
  if (!main) return;
  main.classList.toggle('is-loading', busy);
  main.setAttribute('aria-busy', busy ? 'true' : 'false');
}

async function withViewLoading(task) {
  const token = ++viewLoadToken;
  setViewLoading(true);
  try {
    return await task();
  } finally {
    if (token === viewLoadToken) setViewLoading(false);
  }
}

function scrollMainToTop() {
  const main = document.querySelector('.main-area');
  if (!main) return;
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  main.scrollTo({ top: 0, behavior: reduce ? 'auto' : 'smooth' });
}

async function api(path, options = {}) {
  const headers = { ...(options.headers || {}) };
  if (options.body !== undefined) headers['Content-Type'] = 'application/json';
  const token = getToken();
  if (token) headers.Authorization = `Bearer ${token}`;

  const response = await fetch(`${API_BASE}${path}`, { ...options, headers });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload.ok === false) {
    const err = new Error(payload.error?.message || `HTTP ${response.status}`);
    err.status = response.status;
    throw err;
  }
  return payload.data;
}

function formatDate(value) {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString('ar-SA', { dateStyle: 'short', timeStyle: 'short' });
}

function statusBadgeClass(status) {
  const map = {
    active: 'active',
    healthy: 'healthy',
    suspended: 'suspended',
    pending: 'pending',
    trial: 'trial',
    stale: 'stale',
    warning: 'warning',
    closed: 'closed',
    expired: 'expired',
    revoked: 'inactive',
    inactive: 'inactive',
    offline: 'offline',
    critical: 'danger',
    danger: 'danger',
    failed: 'danger',
  };
  return map[status] || 'neutral';
}

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

function statusLabel(status) {
  const labels = {
    active: 'نشط',
    healthy: 'سليم',
    suspended: 'معلّق',
    pending: 'معلّق',
    trial: 'تجريبي',
    stale: 'غائب',
    warning: 'تحذير',
    closed: 'مغلق',
    expired: 'منتهٍ',
    revoked: 'غير نشط',
    inactive: 'غير نشط',
    offline: 'غير متصل',
    critical: 'حرج',
    danger: 'خطر',
    failed: 'فشل',
  };
  return labels[status] || status || '—';
}

function renderStoresSummary(companies) {
  const list = companies || [];
  const total = list.length;
  const active = list.filter((c) => c.status === 'active').length;
  const suspended = list.filter((c) => c.status === 'suspended').length;
  const closed = list.filter((c) => c.status === 'closed').length;
  const trial = list.filter((c) => String(c.plan_code || '').toLowerCase() === 'trial').length;

  const badge = document.getElementById('stores-count-badge');
  if (badge) badge.textContent = String(total);

  const summary = document.getElementById('stores-summary');
  if (!summary) return;

  summary.innerHTML = [
    { label: 'إجمالي المتاجر', value: total, tone: 'neutral', icon: '▣' },
    { label: 'نشطة', value: active, tone: 'success', icon: '●' },
    { label: 'معلّقة', value: suspended, tone: 'warning', icon: '◐' },
    { label: 'تجريبي', value: trial, tone: 'info', icon: '◇' },
    { label: 'مغلقة', value: closed, tone: 'danger', icon: '○' },
  ].map((item) => `<div class="stores-stat-card tone-${item.tone}">
      <span class="stores-stat-icon" aria-hidden="true">${item.icon}</span>
      <div>
        <span class="stores-stat-label">${escapeHtml(item.label)}</span>
        <strong class="stores-stat-value">${item.value}</strong>
      </div>
    </div>`).join('');
}

function renderCompaniesRows(companies) {
  const filtered = companiesStatusFilter === 'all'
    ? companies
    : companies.filter((c) => c.status === companiesStatusFilter);

  if (filtered.length === 0) {
    companiesTbody.innerHTML = emptyStateRow(
      6,
      companies.length === 0 ? 'لا توجد متاجر مطابقة لبحثك' : 'لا توجد متاجر ضمن هذا التصنيف',
      '▣',
    );
    return;
  }

  companiesTbody.innerHTML = filtered.map((company) => {
    const devicesLabel = `${company.active_devices || 0} / ${company.max_devices || '?'}`;
    const plan = company.plan_name || company.plan_code || '—';
    const isTrial = String(company.plan_code || '').toLowerCase() === 'trial';
    return `<tr>
      <td>
        <div class="stores-name-cell">
          <strong class="stores-name">${escapeHtml(company.name)}</strong>
          <span class="stores-id muted" dir="ltr">${escapeHtml(String(company.id || '').slice(0, 8))}…</span>
        </div>
      </td>
      <td>
        <div class="stores-owner-cell">
          <span class="stores-owner-email" dir="ltr">${escapeHtml(company.owner_email || '—')}</span>
          ${company.owner_name ? `<span class="muted stores-owner-name">${escapeHtml(company.owner_name)}</span>` : ''}
        </div>
      </td>
      <td><span class="stores-plan-pill ${isTrial ? 'trial' : ''}">${escapeHtml(plan)}</span></td>
      <td><span class="stores-devices">${escapeHtml(devicesLabel)}</span></td>
      <td><span class="badge ${statusBadgeClass(company.status)}">${escapeHtml(statusLabel(company.status))}</span></td>
      <td>
        <button class="btn btn-ghost btn-sm stores-action-btn" type="button" data-company-id="${company.id}" title="تفاصيل">
          <span aria-hidden="true">↗</span>
          تفاصيل
        </button>
      </td>
    </tr>`;
  }).join('');
}

function showLogin() {
  loginView.classList.remove('hidden');
  mainView.classList.add('hidden');
}

function showMain() {
  loginView.classList.add('hidden');
  mainView.classList.remove('hidden');
}

function hideAllViews() {
  document.querySelectorAll('.view-panel').forEach((panel) => panel.classList.add('hidden'));
}

function setView(name) {
  if (name !== 'monitoring') {
    clearInterval(monRefreshTimer);
    monRefreshTimer = null;
  }
  document.querySelectorAll('.nav-btn').forEach((btn) => {
    const active = btn.dataset.view === name;
    btn.classList.toggle('active', active);
    if (active) btn.setAttribute('aria-current', 'page');
    else btn.removeAttribute('aria-current');
  });
  hideAllViews();
  const view = document.getElementById(`${name}-view`);
  if (view) view.classList.remove('hidden');
  selectedCompanyId = null;
  selectedCompany = null;
  scrollMainToTop();

  const load = async () => {
    if (name === 'dashboard') await loadDashboard();
    if (name === 'companies') await loadCompanies();
    if (name === 'sync') await loadSyncDashboard();
    if (name === 'monitoring') await loadMonitoring();
    if (name === 'auditlog') await loadAuditLogPage();
    if (name === 'observability') await loadObservability();
  };

  withViewLoading(load).catch((e) => showToast(e.message, 'error'));
}

function openModal(title, bodyHtml, actions) {
  modalReturnFocus = document.activeElement;
  modalTitle.textContent = title;
  modalBody.innerHTML = bodyHtml;
  modalActions.innerHTML = '';
  for (const action of actions) {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = `btn ${action.className || 'btn-ghost'}`;
    btn.textContent = action.label;
    btn.addEventListener('click', action.onClick);
    modalActions.appendChild(btn);
  }
  modal.classList.remove('hidden');
  document.body.classList.add('modal-open');
  const focusTarget = modalActions.querySelector('button') || modal.querySelector('[data-close-modal]');
  focusTarget?.focus();
}

function closeModal() {
  modal.classList.add('hidden');
  modalBody.innerHTML = '';
  modalActions.innerHTML = '';
  document.body.classList.remove('modal-open');
  if (modalReturnFocus && typeof modalReturnFocus.focus === 'function') {
    modalReturnFocus.focus();
  }
  modalReturnFocus = null;
}

modal?.querySelectorAll('[data-close-modal]').forEach((el) => {
  el.addEventListener('click', closeModal);
});

document.addEventListener('keydown', (event) => {
  if (event.key !== 'Escape') return;
  if (modal && !modal.classList.contains('hidden')) {
    event.preventDefault();
    closeModal();
  }
});

async function bootstrap() {
  const token = getToken();
  if (!token) {
    showLogin();
    document.getElementById('login-email')?.focus();
    return;
  }
  try {
    const me = await api('/me');
    adminEmailEl.textContent = me.email || '';
    showMain();
    await withViewLoading(() => Promise.all([loadDashboard(), loadPlans()]));
  } catch {
    setToken(null);
    showLogin();
    document.getElementById('login-email')?.focus();
  }
}

function kpiCard(value, label, tone = '', icon = '◆', subtitle = '') {
  return `<div class="kpi-card ${tone}">
    <div class="kpi-card-top"><span class="kpi-icon" aria-hidden="true">${icon}</span></div>
    <strong class="kpi-value">${value}</strong>
    <span class="kpi-label">${escapeHtml(label)}</span>
    ${subtitle ? `<span class="kpi-hint">${escapeHtml(subtitle)}</span>` : ''}
  </div>`;
}

function emptyStateRow(colspan, message, icon = '○') {
  return `<tr class="empty-row"><td colspan="${colspan}"><div class="empty-state"><span class="empty-icon" aria-hidden="true">${icon}</span><span class="empty-state-text">${escapeHtml(message)}</span></div></td></tr>`;
}

function emptyPanelState(message, icon = '○') {
  return `<div class="dash-empty"><span class="empty-icon" aria-hidden="true">${icon}</span><span class="empty-state-text">${escapeHtml(message)}</span></div>`;
}

function healthCard(tone, icon, title, value, hint) {
  return `<div class="dash-health-card tone-${escapeHtml(tone)}">
    <span class="dash-health-icon" aria-hidden="true">${icon}</span>
    <div class="dash-health-body">
      <span class="dash-health-title">${escapeHtml(title)}</span>
      <strong class="dash-health-value">${escapeHtml(String(value))}</strong>
      ${hint ? `<span class="dash-health-hint">${escapeHtml(hint)}</span>` : ''}
    </div>
  </div>`;
}

async function loadDashboard() {
  const [data, signupsData, vouchersData] = await Promise.all([
    api('/dashboard'),
    api('/signup-requests?status=pending'),
    api('/vouchers'),
  ]);

  const statusLabels = { healthy: 'سليم', degraded: 'متدهور', critical: 'حرج' };
  const status = data.status || 'healthy';
  dashStatusPill.className = `status-pill ${status}`;
  dashStatusPill.textContent = statusLabels[status] || status;
  dashStatusLine.textContent = `آخر تحديث: ${formatDate(data.timestamp)}`;

  if (data.mail?.configured) {
    dashMailHint.classList.add('hidden');
  } else {
    dashMailHint.classList.remove('hidden');
    dashMailHint.textContent = 'البريد غير مُعدّ — لن يُرسل بريد تلقائي عند الموافقة. أضف إعدادات MAIL_* على الخادم.';
  }

  const s = data.summary || {};
  const warn = (v) => (Number(v) > 0 ? 'warn' : 'ok');
  const danger = (v) => (Number(v) > 0 ? 'danger' : 'ok');
  const voucherCount = (vouchersData.vouchers || []).length;

  dashMetricsCards.innerHTML = [
    kpiCard(s.active_companies || 0, 'متاجر نشطة', 'ok', '▣', `من أصل ${s.total_companies || 0}`),
    kpiCard(s.pending_signups || 0, 'طلبات معلّقة', warn(s.pending_signups), '◐', 'بانتظار المراجعة'),
    kpiCard(s.active_devices || 0, 'أجهزة نشطة', 'ok', '▣', 'متصلة حالياً'),
    kpiCard(s.stale_devices || 0, 'أجهزة غائبة', warn(s.stale_devices), '◌', '+24 ساعة'),
    kpiCard(s.subscriptions_expiring_30d || 0, 'اشتراكات تنتهي', warn(s.subscriptions_expiring_30d), '◷', 'خلال 30 يوماً'),
    kpiCard(s.pending_sync_queue || 0, 'طابور المزامنة', warn(s.pending_sync_queue), '↻', 'عناصر بالانتظار'),
    kpiCard(s.failed_sync_queue || 0, 'أخطاء sync', danger(s.failed_sync_queue), '!', 'تحتاج متابعة'),
    kpiCard(s.pending_conflicts || 0, 'تعارضات', warn(s.pending_conflicts), '⇄', 'معلّقة'),
  ].join('');

  const platformTone = status === 'critical' ? 'danger' : status === 'degraded' ? 'warning' : 'success';
  const mailConfigured = !!data.mail?.configured;
  if (dashHealthCards) {
    dashHealthCards.innerHTML = [
      healthCard(platformTone, '◎', 'حالة المنصة', statusLabels[status] || status, formatDate(data.timestamp)),
      healthCard(mailConfigured ? 'info' : 'warning', '✉', 'البريد التلقائي', mailConfigured ? 'مفعّل' : 'غير مُعدّ', mailConfigured ? 'إشعارات الموافقة جاهزة' : 'لن يُرسل بريد تلقائي'),
      healthCard(Number(s.failed_sync_queue) > 0 ? 'danger' : 'success', '↻', 'المزامنة', Number(s.failed_sync_queue) > 0 ? `${s.failed_sync_queue} خطأ` : 'مستقرة', `${s.pending_sync_queue || 0} في الطابور`),
      healthCard(Number(s.stale_devices) > 0 ? 'warning' : 'success', '▣', 'الأجهزة', `${s.active_devices || 0} نشط`, Number(s.stale_devices) > 0 ? `${s.stale_devices} غائب` : 'لا أجهزة غائبة'),
    ].join('');
  }

  const pendingSignups = signupsData.requests || [];
  dashPendingBadge.textContent = String(pendingSignups.length);

  dashSignupsTbody.innerHTML = pendingSignups.length === 0
    ? emptyStateRow(6, 'لا طلبات معلّقة — كل شيء تحت السيطرة', '✓')
    : pendingSignups.map((row) => `<tr>
        <td><strong>${escapeHtml(row.store_name)}</strong>${row.owner_name ? `<br><span class="muted">${escapeHtml(row.owner_name)}</span>` : ''}</td>
        <td dir="ltr" class="ltr-cell">${escapeHtml(row.email)}</td>
        <td>${escapeHtml(row.desired_plan_code || '—')}</td>
        <td>${row.voucher_code ? `<code>${escapeHtml(row.voucher_code)}</code>` : '<span class="muted">—</span>'}</td>
        <td class="muted">${formatDate(row.created_at)}</td>
        <td>
          <div class="action-group">
            <button class="btn btn-success btn-sm" type="button" data-approve="${row.id}">موافقة</button>
            <button class="btn btn-danger btn-sm" type="button" data-reject="${row.id}">رفض</button>
          </div>
        </td>
      </tr>`).join('');

  const vouchers = (vouchersData.vouchers || []).slice(0, 10);
  dashVouchersTbody.innerHTML = vouchers.length === 0
    ? emptyStateRow(5, 'لا توجد أكواد دعوة بعد — أنشئ كوداً من الإجراءات السريعة', '◇')
    : vouchers.map((row) => `<tr>
        <td><code>${escapeHtml(row.code)}</code></td>
        <td>${escapeHtml(row.plan_code)}</td>
        <td>${escapeHtml(row.used_count)} / ${escapeHtml(row.max_uses)}</td>
        <td>${row.is_active ? '<span class="badge active">نشط</span>' : '<span class="badge inactive">معطّل</span>'}</td>
        <td class="muted">${row.expires_at ? escapeHtml(String(row.expires_at).slice(0, 10)) : '—'}</td>
      </tr>`).join('');

  const alerts = data.alerts || [];
  dashAlerts.innerHTML = alerts.length === 0
    ? emptyPanelState('لا تنبيهات حالياً — المنصة هادئة', '✓')
    : alerts.slice(0, 8).map((a) => {
      const severity = a.severity || 'info';
      const icon = severity === 'critical' ? '!' : severity === 'warning' ? '⚠' : '•';
      return `<div class="dash-timeline-item ${escapeHtml(severity)}">
        <span class="dash-timeline-dot" aria-hidden="true">${icon}</span>
        <div class="dash-timeline-content">
          <p class="dash-timeline-message">${escapeHtml(a.message)}</p>
          ${a.company_name ? `<span class="dash-timeline-meta">${escapeHtml(a.company_name)}</span>` : ''}
        </div>
      </div>`;
    }).join('');

  dashQuickSummary.innerHTML = [
    { label: 'إجمالي المتاجر', value: s.total_companies || 0, icon: '▣' },
    { label: 'أجهزة نشطة', value: s.active_devices || 0, icon: '◉' },
    { label: 'طلبات معلّقة', value: pendingSignups.length, icon: '◐' },
    { label: 'أكواد الدعوة', value: voucherCount, icon: '◇' },
    { label: 'البريد التلقائي', value: mailConfigured ? 'مفعّل' : 'غير مُعدّ', icon: '✉' },
  ].map((item) => `<div class="dash-summary-item">
      <span class="dash-summary-icon" aria-hidden="true">${item.icon}</span>
      <div>
        <span class="dash-summary-label">${escapeHtml(item.label)}</span>
        <strong class="dash-summary-value">${escapeHtml(String(item.value))}</strong>
      </div>
    </div>`).join('');
}

function showSignupWelcome(text) {
  lastWelcomeCard = text;
  signupResult.textContent = text;
  signupResultWrap.classList.remove('hidden');
}

function showCreateWelcome(text) {
  lastWelcomeCard = text;
  createResult.textContent = text;
  createResultWrap.classList.remove('hidden');
}

function handleApproveSignup(requestId) {
  openModal(
    'موافقة على الطلب',
    `<p class="muted" style="margin-top:0">سيتم إنشاء المتجر وإرسال بريد للعميل تلقائياً.</p>
     <label class="field">
       <span>كلمة مرور المالك (اتركها فارغة للتوليد التلقائي)</span>
       <input type="password" id="modal-password" minlength="8" placeholder="8 أحرف على الأقل">
     </label>`,
    [
      { label: 'إلغاء', className: 'btn-ghost', onClick: closeModal },
      {
        label: 'موافقة وإرسال',
        className: 'btn-primary',
        onClick: async () => {
          const password = document.getElementById('modal-password')?.value?.trim() || '';
          if (password !== '' && password.length < 8) {
            showToast('كلمة المرور 8 أحرف على الأقل', 'error');
            return;
          }
          closeModal();
          try {
            const body = password ? { password, send_email: true } : { send_email: true };
            const result = await api(`/signup-requests/${requestId}/approve`, {
              method: 'POST',
              body: JSON.stringify(body),
            });
            const card = result.tenant?.welcome_card || '';
            if (card) {
              showSignupWelcome(card);
              navigator.clipboard.writeText(card).catch(() => {});
            }
            if (result.email?.sent) showToast('تمت الموافقة وإرسال البريد', 'success');
            else if (result.email?.error) showToast(`تمت الموافقة — البريد: ${result.email.error}`, 'info');
            else showToast('تمت الموافقة وإنشاء المتجر', 'success');
            await loadDashboard();
          } catch (error) {
            showToast(error.message, 'error');
          }
        },
      },
    ],
  );
}

function handleRejectSignup(requestId) {
  openModal(
    'رفض الطلب',
    `<label class="field">
       <span>سبب الرفض (يُرسل للعميل)</span>
       <input type="text" id="modal-reason" value="لم يتم قبول الطلب في الوقت الحالي">
     </label>`,
    [
      { label: 'إلغاء', className: 'btn-ghost', onClick: closeModal },
      {
        label: 'رفض وإرسال',
        className: 'btn-danger',
        onClick: async () => {
          const reason = document.getElementById('modal-reason')?.value?.trim() || 'Rejected by ops';
          closeModal();
          try {
            await api(`/signup-requests/${requestId}/reject`, {
              method: 'POST',
              body: JSON.stringify({ reason, send_email: true }),
            });
            showToast('تم رفض الطلب', 'success');
            await loadDashboard();
          } catch (error) {
            showToast(error.message, 'error');
          }
        },
      },
    ],
  );
}

dashSignupsTbody?.addEventListener('click', (event) => {
  const approveBtn = event.target.closest('[data-approve]');
  const rejectBtn = event.target.closest('[data-reject]');
  if (approveBtn) handleApproveSignup(approveBtn.dataset.approve);
  if (rejectBtn) handleRejectSignup(rejectBtn.dataset.reject);
});

async function loadCompanies() {
  const q = companySearch.value.trim();
  const path = q ? `/companies?q=${encodeURIComponent(q)}` : '/companies';
  const data = await api(path);
  companiesCache = data.companies || [];
  renderStoresSummary(companiesCache);
  renderCompaniesRows(companiesCache);
}

function planOptionsHtml(selectedCode) {
  return plansCache.map((plan) => {
    const selected = plan.code === selectedCode ? 'selected' : '';
    return `<option value="${escapeHtml(plan.code)}" ${selected}>${escapeHtml(plan.name)} (${plan.max_devices})</option>`;
  }).join('');
}

async function openCompany(companyId) {
  selectedCompanyId = companyId;
  hideAllViews();
  document.getElementById('company-detail-view').classList.remove('hidden');
  document.querySelectorAll('.nav-btn').forEach((btn) => {
    const active = btn.dataset.view === 'companies';
    btn.classList.toggle('active', active);
    if (active) btn.setAttribute('aria-current', 'page');
    else btn.removeAttribute('aria-current');
  });
  scrollMainToTop();
  setViewLoading(true);
  try {
    const [{ company }, { devices }, syncData] = await Promise.all([
      api(`/companies/${companyId}`),
      api(`/companies/${companyId}/devices`),
      api(`/companies/${companyId}/sync-health`),
    ]);
    selectedCompany = company;
    const health = syncData.health || null;

    renderStoreCommandCenter(company, devices || [], health);
    bindCompanyDetailActions();
  } finally {
    setViewLoading(false);
  }
}

function renderStoreCommandCenter(company, devices, health) {
  const queue = health?.queue || {};
  const pending = queue.pending || 0;
  const failed = (queue.rejected || 0) + (queue.conflict || 0);
  const conflictsPending = health?.conflicts?.pending || 0;
  const staleCount = (health?.devices || []).filter((d) => d.is_stale === true || d.is_stale === 't' || d.is_stale === 1).length;
  const lastSync = health?.changelog?.last_occurred_at ? formatDate(health.changelog.last_occurred_at) : '—';
  const activeDevices = company.active_devices || devices.filter((d) => !(d.revoked_at || d.status === 'revoked')).length;
  const isActive = company.status === 'active';
  const isClosed = company.status === 'closed';
  const statusAction = isActive
    ? '<button class="btn btn-danger" id="suspend-company" type="button">تعليق</button>'
    : '<button class="btn btn-primary" id="activate-company" type="button">تفعيل</button>';

  const cloudTone = failed > 0 || conflictsPending > 0
    ? 'danger'
    : pending > 0 || staleCount > 0 || company.status !== 'active'
      ? 'warning'
      : 'success';
  const cloudLabel = cloudTone === 'danger' ? 'يتطلب اهتماماً' : cloudTone === 'warning' ? 'يحتاج متابعة' : 'مستقر';

  const headerEl = document.getElementById('cc-header');
  if (headerEl) {
    headerEl.innerHTML = `
      <div class="cc-header-main">
        <p class="eyebrow">مركز قيادة المتجر</p>
        <h1 class="cc-store-title">${escapeHtml(company.name)}</h1>
        <div class="cc-header-meta">
          <span class="badge ${statusBadgeClass(company.status)}">${escapeHtml(statusLabel(company.status))}</span>
          <span class="cc-plan-badge ${String(company.plan_code || '').toLowerCase() === 'trial' ? 'trial' : ''}">${escapeHtml(company.plan_name || company.plan_code || '—')}</span>
          <span class="cc-id-chip" dir="ltr">
            <code>${escapeHtml(company.id)}</code>
            <button class="btn btn-ghost btn-sm" type="button" data-copy="${company.id}">نسخ</button>
          </span>
        </div>
        <p class="muted cc-owner-line">${escapeHtml(company.owner_name || '')}${company.owner_name && company.owner_email ? ' · ' : ''}<span dir="ltr">${escapeHtml(company.owner_email || '')}</span></p>
      </div>
      <div class="cc-header-actions">
        <button class="btn btn-secondary" id="welcome-card" type="button">بطاقة ترحيب</button>
        ${statusAction}
        ${isClosed ? '' : '<button class="btn btn-danger" id="close-company" type="button">إغلاق</button>'}
      </div>
    `;
  }

  const summaryEl = document.getElementById('cc-summary-cards');
  if (summaryEl) {
    summaryEl.innerHTML = [
      { label: 'حالة المتجر', value: statusLabel(company.status), hint: company.status, tone: company.status === 'active' ? 'success' : company.status === 'suspended' ? 'warning' : 'danger', icon: '◎' },
      { label: 'الاشتراك', value: company.plan_name || company.plan_code || '—', hint: `${activeDevices}/${company.max_devices || '?'} جهاز`, tone: 'info', icon: '◇' },
      { label: 'الأجهزة المتصلة', value: String(activeDevices), hint: staleCount > 0 ? `${staleCount} غائب` : 'لا أجهزة غائبة', tone: staleCount > 0 ? 'warning' : 'success', icon: '▣' },
      { label: 'آخر مزامنة', value: lastSync, hint: health?.changelog?.total_events != null ? `${health.changelog.total_events} حدث` : '—', tone: 'neutral', icon: '↻' },
      { label: 'حالة السحابة', value: cloudLabel, hint: `${pending} في الطابور · ${failed} فاشل`, tone: cloudTone, icon: '☁' },
    ].map((card) => `<div class="cc-summary-card tone-${card.tone}">
        <span class="cc-summary-icon" aria-hidden="true">${card.icon}</span>
        <div>
          <span class="cc-summary-label">${escapeHtml(card.label)}</span>
          <strong class="cc-summary-value">${escapeHtml(String(card.value))}</strong>
          <span class="cc-summary-hint">${escapeHtml(card.hint)}</span>
        </div>
      </div>`).join('');
  }

  companySummary.innerHTML = `
    <div class="panel-head">
      <div>
        <h2>معلومات المتجر والاشتراك</h2>
        <p class="muted">إدارة الخطة والحساب وكلمة المرور</p>
      </div>
    </div>
    <div class="cc-info-grid">
      <div class="cc-info-item"><span>الفرع الافتراضي</span><strong>${escapeHtml(company.default_branch_name || '—')}</strong></div>
      <div class="cc-info-item"><span>العملة</span><strong>${escapeHtml(company.default_currency_code || '—')}</strong></div>
      <div class="cc-info-item"><span>اللغة</span><strong>${escapeHtml(company.default_locale || '—')}</strong></div>
      <div class="cc-info-item"><span>تاريخ الإنشاء</span><strong>${escapeHtml(formatDate(company.created_at))}</strong></div>
    </div>
    <div class="cc-form-block">
      <h3 class="cc-block-title">تغيير الخطة</h3>
      <div class="actions-row">
        <select id="detail-plan">${planOptionsHtml(company.plan_code)}</select>
        <button class="btn btn-secondary" id="save-plan" type="button">حفظ الخطة</button>
      </div>
    </div>
    <div class="cc-form-block">
      <h3 class="cc-block-title">تمديد الاشتراك</h3>
      <div class="actions-row">
        <input type="number" id="extend-days" min="1" max="365" value="30" style="width:110px">
        <button class="btn btn-secondary" id="extend-subscription" type="button">تمديد</button>
      </div>
    </div>
    <div class="cc-form-block">
      <h3 class="cc-block-title">إعادة تعيين كلمة مرور المالك</h3>
      <div class="actions-row">
        <input type="password" id="new-owner-password" placeholder="كلمة مرور جديدة" minlength="8">
        <button class="btn btn-secondary" id="reset-password" type="button">إعادة تعيين</button>
      </div>
    </div>
    <div class="actions-row danger-zone">
      <button class="btn btn-danger" id="delete-company" type="button">حذف المتجر نهائياً</button>
    </div>
    <pre id="detail-welcome" class="result hidden"></pre>
  `;

  renderCompanySyncHealth(health, company.name);
  renderStoreHealthCard(cloudTone, cloudLabel, pending, failed, conflictsPending, staleCount, lastSync);
  renderStoreActivity(health);
  renderStoreWarnings(company, pending, failed, conflictsPending, staleCount);
  renderStoreQuickActions(isActive, isClosed);

  const staleMap = new Map();
  for (const d of health?.devices || []) {
    staleMap.set(d.id, d.is_stale === true || d.is_stale === 't' || d.is_stale === 1);
  }

  if (!devices.length) {
    devicesTbody.innerHTML = `<div class="cc-empty">${emptyPanelState('لا توجد أجهزة مسجّلة لهذا المتجر', '▣')}</div>`;
    return;
  }

  devicesTbody.innerHTML = devices.map((device) => {
    const revoked = device.revoked_at || device.status === 'revoked';
    const isStale = !revoked && staleMap.get(device.id);
    return `<article class="cc-device-card ${revoked ? 'is-revoked' : ''} ${isStale ? 'is-stale' : ''}">
      <div class="cc-device-top">
        <strong class="cc-device-name">${escapeHtml(device.device_name || 'جهاز')}</strong>
        <span class="badge ${revoked ? 'inactive' : 'active'}">${revoked ? 'ملغى' : 'نشط'}</span>
      </div>
      <div class="cc-device-meta">
        <span>${escapeHtml(device.platform || '—')}</span>
        <span>${escapeHtml(device.app_version || '—')}</span>
      </div>
      <div class="cc-device-footer">
        <span class="muted">آخر ظهور: ${formatDate(device.last_seen_at)}${isStale ? ' · غائب' : ''}</span>
        ${revoked ? '' : `<button class="btn btn-danger btn-sm" type="button" data-revoke="${device.id}">إلغاء</button>`}
      </div>
    </article>`;
  }).join('');
}

function renderStoreHealthCard(tone, label, pending, failed, conflicts, stale, lastSync) {
  const el = document.getElementById('cc-health');
  if (!el) return;
  el.innerHTML = `
    <div class="panel-head">
      <div>
        <h2>صحة البنية</h2>
        <p class="muted">مؤشر صحة متجر السحابة</p>
      </div>
    </div>
    <div class="cc-health-hero tone-${tone}">
      <span class="cc-health-orb" aria-hidden="true"></span>
      <div>
        <strong>${escapeHtml(label)}</strong>
        <span>آخر مزامنة: ${escapeHtml(lastSync)}</span>
      </div>
    </div>
    <div class="cc-health-metrics">
      <div><span>الطابور</span><strong>${pending}</strong></div>
      <div><span>فاشل</span><strong>${failed}</strong></div>
      <div><span>تعارض</span><strong>${conflicts}</strong></div>
      <div><span>غائب</span><strong>${stale}</strong></div>
    </div>
  `;
}

function renderStoreActivity(health) {
  const el = document.getElementById('cc-activity');
  if (!el) return;
  const recent = health?.changelog?.recent || [];
  el.innerHTML = `
    <div class="panel-head">
      <div>
        <h2>النشاط الأخير</h2>
        <p class="muted">آخر أحداث المزامنة</p>
      </div>
    </div>
    ${recent.length === 0
      ? emptyPanelState('لا يوجد نشاط مزامنة حديث', '↻')
      : `<div class="cc-timeline">${recent.slice(0, 10).map((row) => `
          <div class="cc-timeline-item">
            <span class="cc-timeline-dot" aria-hidden="true">↻</span>
            <div>
              <strong>${escapeHtml(row.entity_type || 'كيان')} · ${escapeHtml(row.operation || '—')}</strong>
              <span class="muted">${formatDate(row.occurred_at)}</span>
            </div>
          </div>`).join('')}</div>`}
  `;
}

function renderStoreWarnings(company, pending, failed, conflicts, stale) {
  const el = document.getElementById('cc-warnings');
  if (!el) return;
  const warnings = [];
  if (company.status === 'suspended') warnings.push({ tone: 'warning', text: 'المتجر معلّق حالياً' });
  if (company.status === 'closed') warnings.push({ tone: 'danger', text: 'المتجر مغلق ولن تتم المزامنة' });
  if (failed > 0) warnings.push({ tone: 'danger', text: `${failed} عنصر مزامنة فاشل` });
  if (conflicts > 0) warnings.push({ tone: 'warning', text: `${conflicts} تعارض معلّق` });
  if (pending >= 50) warnings.push({ tone: 'warning', text: `تراكم في الطابور: ${pending}` });
  if (stale > 0) warnings.push({ tone: 'warning', text: `${stale} جهاز غائب لأكثر من 24 ساعة` });

  el.innerHTML = `
    <div class="panel-head">
      <div>
        <h2>التنبيهات</h2>
        <p class="muted">إشارات تحتاج متابعة</p>
      </div>
    </div>
    ${warnings.length === 0
      ? emptyPanelState('لا تنبيهات — المتجر يبدو بخير', '✓')
      : `<div class="cc-warnings-stack">${warnings.map((w) => `
          <div class="cc-warning-item tone-${w.tone}">${escapeHtml(w.text)}</div>`).join('')}</div>`}
  `;
}

function renderStoreQuickActions(isActive, isClosed) {
  const el = document.getElementById('cc-quick-actions');
  if (!el) return;
  el.innerHTML = `
    <div class="panel-head">
      <div>
        <h2>إجراءات سريعة</h2>
        <p class="muted">اختصارات لإدارة المتجر</p>
      </div>
    </div>
    <div class="cc-quick-grid">
      <button class="btn btn-secondary cc-quick-btn" type="button" data-cc-action="welcome">بطاقة ترحيب</button>
      <button class="btn btn-secondary cc-quick-btn" type="button" data-cc-action="plan">التركيز على الخطة</button>
      ${isActive
        ? '<button class="btn btn-danger cc-quick-btn" type="button" data-cc-action="suspend">تعليق المتجر</button>'
        : '<button class="btn btn-primary cc-quick-btn" type="button" data-cc-action="activate">تفعيل المتجر</button>'}
      ${isClosed ? '' : '<button class="btn btn-danger cc-quick-btn" type="button" data-cc-action="close">إغلاق المتجر</button>'}
    </div>
  `;
}

function renderCompanySyncHealth(health, companyName) {
  if (!health) {
    companySyncHealth.classList.add('hidden');
    return;
  }
  const queue = health.queue || {};
  const pending = queue.pending || 0;
  const failed = (queue.rejected || 0) + (queue.conflict || 0);
  const conflictsPending = health.conflicts?.pending || 0;
  const staleCount = (health.devices || []).filter((d) => d.is_stale === true || d.is_stale === 't').length;
  const syncTone = failed > 0 || conflictsPending > 0 ? 'danger' : pending > 0 || staleCount > 0 ? 'warning' : 'success';

  companySyncHealth.innerHTML = `
    <div class="panel-head">
      <div>
        <h2>المزامنة</h2>
        <p class="muted">حالة طابور السحابة لـ ${escapeHtml(companyName)}</p>
      </div>
      <span class="status-pill ${syncTone === 'success' ? 'healthy' : syncTone === 'warning' ? 'degraded' : 'critical'}">${syncTone === 'success' ? 'مستقرة' : syncTone === 'warning' ? 'متعثرة' : 'حرجة'}</span>
    </div>
    <div class="cc-sync-grid">
      ${kpiCard(pending, 'في الانتظار', pending > 0 ? 'warn' : 'ok', '↻', 'عناصر الطابور')}
      ${kpiCard(failed, 'فاشل', failed > 0 ? 'danger' : 'ok', '!', 'rejected / conflict')}
      ${kpiCard(conflictsPending, 'تعارض', conflictsPending > 0 ? 'danger' : 'ok', '⇄', 'معلّق')}
      ${kpiCard(staleCount, 'غائب', staleCount > 0 ? 'warn' : 'ok', '◌', '+24 ساعة')}
    </div>
    <div class="cc-sync-meta">
      <div><span>آخر مزامنة</span><strong>${health.changelog?.last_occurred_at ? formatDate(health.changelog.last_occurred_at) : '—'}</strong></div>
      <div><span>آخر تسلسل</span><strong dir="ltr">${health.changelog?.last_sequence ?? '—'}</strong></div>
      <div><span>إجمالي الأحداث</span><strong>${health.changelog?.total_events ?? 0}</strong></div>
    </div>
  `;
  companySyncHealth.classList.remove('hidden');
}

async function loadSyncDashboard() {
  const [overviewData, failuresData, conflictsData] = await Promise.all([
    api('/sync/overview'),
    api('/sync/failures?limit=30'),
    api('/sync/conflicts?status=pending&limit=30'),
  ]);

  const o = overviewData.overview || {};
  const tone = (v, w = 1) => (Number(v) >= w * 5 ? 'danger' : Number(v) >= w ? 'warn' : 'ok');

  syncOverviewCards.innerHTML = [
    kpiCard(o.pending_queue || 0, 'طابور انتظار', tone(o.pending_queue), '↻'),
    kpiCard(o.failed_queue || 0, 'فاشل', tone(o.failed_queue), '!'),
    kpiCard(o.pending_conflicts || 0, 'تعارض', tone(o.pending_conflicts), '⇄'),
    kpiCard(o.stale_devices || 0, 'جهاز غائب', tone(o.stale_devices), '◌'),
  ].join('');

  const renderTable = (tbody, rows, cols, emptyMsg, emptyIcon = '○') => {
    if (rows.length === 0) {
      tbody.innerHTML = emptyStateRow(cols, emptyMsg, emptyIcon);
      return;
    }
    tbody.innerHTML = rows.map((r) => r).join('');
  };

  renderTable(
    staleDevicesTbody,
    (overviewData.stale_devices || []).map((d) => `<tr>
      <td>${escapeHtml(d.company_name)}</td>
      <td>${escapeHtml(d.device_name)}</td>
      <td>${escapeHtml(d.platform)}</td>
      <td>${formatDate(d.last_seen_at)}</td>
      <td><button class="btn btn-ghost btn-sm" data-company-id="${d.company_id}">تفاصيل</button></td>
    </tr>`),
    5,
    'لا أجهزة غائبة',
    '◌',
  );

  renderTable(
    syncFailuresTbody,
    (failuresData.failures || []).map((row) => `<tr>
      <td>${escapeHtml(row.company_name)}</td>
      <td>${escapeHtml(row.entity_type)} / ${escapeHtml(row.operation)}</td>
      <td><span class="badge ${statusBadgeClass(row.status)}">${escapeHtml(statusLabel(row.status))}</span></td>
      <td>${escapeHtml(row.error_code || row.error_detail || '—')}</td>
      <td>${formatDate(row.received_at)}</td>
    </tr>`),
    5,
    'لا أخطاء',
    '✓',
  );

  renderTable(
    syncConflictsTbody,
    (conflictsData.conflicts || []).map((row) => `<tr>
      <td>${escapeHtml(row.company_name)}</td>
      <td>${escapeHtml(row.entity_type)} / ${escapeHtml(row.operation)}</td>
      <td>${escapeHtml(row.conflict_kind)}</td>
      <td><span class="badge ${statusBadgeClass(row.status)}">${escapeHtml(statusLabel(row.status))}</span></td>
      <td>${formatDate(row.created_at)}</td>
    </tr>`),
    5,
    'لا تعارضات',
    '⇄',
  );
}

function formatBytes(bytes) {
  if (bytes == null) return '—';
  const units = ['B', 'KB', 'MB', 'GB'];
  let value = Number(bytes);
  let i = 0;
  while (value >= 1024 && i < units.length - 1) { value /= 1024; i += 1; }
  return `${value.toFixed(1)} ${units[i]}`;
}

async function loadObservability() {
  const data = await api('/observability/overview');
  const statusLabels = { healthy: 'سليم', degraded: 'متدهور', critical: 'حرج' };
  const status = data.status || 'healthy';
  obsStatusBanner.className = `status-pill wide ${status}`;
  obsStatusBanner.textContent = `حالة المنصة: ${statusLabels[status] || status} · ${formatDate(data.timestamp)}`;

  const m = data.metrics || {};
  obsMetricsCards.innerHTML = [
    kpiCard(m.active_companies || 0, 'متاجر نشطة', 'ok', '▣'),
    kpiCard(m.active_devices || 0, 'أجهزة نشطة', 'ok', '▣'),
    kpiCard(m.sync_events_total || 0, 'أحداث sync', 'ok', '↻'),
    kpiCard(m.audit_events_total || 0, 'سجلات audit', 'ok', '◎'),
  ].join('');

  const alerts = data.alerts || [];
  obsAlerts.innerHTML = alerts.length === 0
    ? '<p class="alert-empty"><span class="empty-icon" aria-hidden="true">✓</span><span>لا تنبيهات</span></p>'
    : alerts.map((a) => `<div class="alert-item ${escapeHtml(a.severity)}">${escapeHtml(a.message)}</div>`).join('');

  const db = data.database || {};
  const logs = data.logs || {};
  const logRecent = logs.recent || {};
  const app = data.application || {};
  const storagePaths = data.storage?.paths || {};
  const storageCards = Object.entries(storagePaths).map(([name, info]) =>
    `<div class="infra-card"><div class="infra-card-label">${escapeHtml(name)}</div><div class="infra-card-value">${info.writable ? 'قابل للكتابة' : 'غير قابل'} · ${info.free_percent ?? '?'}%</div></div>`,
  ).join('');

  obsInfra.innerHTML = `<div class="infra-cards">
    <div class="infra-card"><div class="infra-card-label">التطبيق</div><div class="infra-card-value">${escapeHtml(app.name)} · ${escapeHtml(app.environment)} · PHP ${escapeHtml(app.php_version)}</div></div>
    <div class="infra-card"><div class="infra-card-label">قاعدة البيانات</div><div class="infra-card-value">${db.connected ? `متصل · ${db.latency_ms}ms` : 'غير متصل'}</div></div>
    <div class="infra-card"><div class="infra-card-label">السجلات</div><div class="infra-card-value">${formatBytes(logs.size_bytes)} · ${logRecent.error || 0} خطأ / ساعة</div></div>
    ${storageCards}
  </div>`;

  await loadAuditLogs();
}

async function loadAuditLogs() {
  const companyId = document.getElementById('audit-company-id').value.trim();
  const action = document.getElementById('audit-action').value.trim();
  const params = new URLSearchParams({ limit: '40' });
  if (companyId) params.set('company_id', companyId);
  if (action) params.set('action', action);

  const data = await api(`/audit-logs?${params.toString()}`);
  if ((data.entries || []).length === 0) {
    auditTbody.innerHTML = emptyStateRow(5, 'لا سجلات', '◎');
  } else {
    auditTbody.innerHTML = (data.entries || []).map((row) => `<tr>
      <td>${formatDate(row.created_at)}</td>
      <td>${escapeHtml(row.company_name)}</td>
      <td>${escapeHtml(row.action)}</td>
      <td>${escapeHtml(row.entity_type || '—')}</td>
      <td>${escapeHtml(row.ip_address || '—')}</td>
    </tr>`).join('');
  }
  auditMeta.textContent = `عرض ${data.entries?.length || 0} من ${data.total || 0}`;
}

function monFilterParams() {
  const params = new URLSearchParams();
  const org = document.getElementById('mon-filter-org')?.value.trim();
  const branch = document.getElementById('mon-filter-branch')?.value.trim();
  const device = document.getElementById('mon-filter-device')?.value.trim();
  const from = document.getElementById('mon-filter-from')?.value;
  const to = document.getElementById('mon-filter-to')?.value;
  const type = document.getElementById('mon-filter-type')?.value.trim();
  const status = document.getElementById('mon-filter-status')?.value;
  if (org) params.set('company_id', org);
  if (branch) params.set('branch_id', branch);
  if (device) params.set('device_id', device);
  if (from) params.set('date_from', from);
  if (to) params.set('date_to', to);
  if (type) params.set('sync_type', type);
  if (status) params.set('status', status);
  return params;
}

function monMetricCard(value, label, tone = 'ok', hint = '') {
  return `<article class="kpi-card ${tone}">
    <div class="kpi-card-top"><span class="kpi-icon" aria-hidden="true">◉</span></div>
    <div class="kpi-value">${escapeHtml(String(value ?? '—'))}</div>
    <div class="kpi-label">${escapeHtml(label)}</div>
    ${hint ? `<div class="mon-card-meta">${escapeHtml(hint)}</div>` : ''}
  </article>`;
}

function monHealthCard(key, card) {
  const titles = {
    cloud: 'Cloud Status',
    database: 'Database Status',
    queue: 'Queue Status',
    sync_service: 'Sync Service Status',
    active_workers: 'Active Workers',
    connected_devices: 'Connected Devices',
    online_organizations: 'Online Organizations',
  };
  const tone = card.color === 'green' ? 'ok' : (card.color === 'amber' ? 'warn' : 'danger');
  const latency = card.latency_ms != null ? `${card.latency_ms} ms` : '—';
  return `<article class="kpi-card ${tone}">
    <div class="kpi-card-top"><span class="mon-health-state"><span class="mon-dot ${escapeHtml(card.color || 'red')}"></span>${escapeHtml(titles[key] || key)}</span></div>
    <div class="kpi-value">${escapeHtml(card.label || '—')}</div>
    <div class="kpi-label">الحالة</div>
    <div class="mon-card-meta">آخر تحديث: ${formatDate(card.updated_at)} · زمن الاستجابة: ${escapeHtml(latency)}</div>
  </article>`;
}

function monSparkline(points, valueKey, stroke) {
  if (!points.length) return '<div class="mon-chart-empty">لا بيانات</div>';
  const values = points.map((p) => Number(p[valueKey] || 0));
  const max = Math.max(...values, 1);
  const w = 320;
  const h = 100;
  const step = values.length > 1 ? w / (values.length - 1) : w;
  const coords = values.map((v, i) => {
    const x = i * step;
    const y = h - (v / max) * (h - 12) - 6;
    return `${x.toFixed(1)},${y.toFixed(1)}`;
  }).join(' ');
  return `<svg viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" aria-hidden="true">
    <polyline fill="none" stroke="${stroke}" stroke-width="2.5" points="${coords}"></polyline>
  </svg>`;
}

function monBars(points, successKey, failKey) {
  if (!points.length) return '<div class="mon-chart-empty">لا بيانات</div>';
  const w = 320;
  const h = 100;
  const n = points.length;
  const gap = 2;
  const barW = Math.max(2, (w - gap * n) / n);
  let max = 1;
  points.forEach((p) => {
    max = Math.max(max, Number(p[successKey] || 0) + Number(p[failKey] || 0));
  });
  const rects = points.map((p, i) => {
    const s = Number(p[successKey] || 0);
    const f = Number(p[failKey] || 0);
    const total = s + f;
    const bh = (total / max) * (h - 8);
    const x = i * (barW + gap);
    const y = h - bh;
    const sh = total > 0 ? (s / total) * bh : 0;
    return `<rect x="${x}" y="${y + (bh - sh)}" width="${barW}" height="${sh}" fill="#10B981"></rect>
      <rect x="${x}" y="${y}" width="${barW}" height="${Math.max(0, bh - sh)}" fill="#EF4444"></rect>`;
  }).join('');
  return `<svg viewBox="0 0 ${w} ${h}" preserveAspectRatio="none">${rects}</svg>`;
}

function scheduleMonAutoRefresh() {
  clearInterval(monRefreshTimer);
  monRefreshTimer = null;
  const enabled = document.getElementById('mon-auto-refresh')?.checked;
  const view = document.getElementById('monitoring-view');
  if (!enabled || !view || view.classList.contains('hidden')) return;
  monRefreshTimer = setInterval(() => {
    loadMonitoring({ silent: true }).catch(() => {});
  }, 10000);
}

async function loadMonitoring(opts = {}) {
  const silent = !!opts.silent;
  const params = monFilterParams();
  const data = await api(`/monitoring/overview?${params.toString()}`);
  monLatest = data;
  const updated = document.getElementById('mon-updated');
  if (updated) updated.textContent = `آخر تحديث: ${formatDate(data.timestamp)} · ${data.generated_in_ms ?? '—'} ms`;

  const alerts = data.alerts || [];
  const banner = document.getElementById('mon-alert-banner');
  if (banner) {
    if (alerts.length === 0) {
      banner.classList.add('hidden');
      banner.textContent = '';
    } else {
      banner.classList.remove('hidden');
      banner.innerHTML = alerts.map((a) => `⚠ ${escapeHtml(a.message)} (${escapeHtml(String(a.value ?? ''))})`).join(' · ');
    }
  }

  const health = data.health || {};
  document.getElementById('mon-health-cards').innerHTML = Object.keys(health)
    .map((key) => monHealthCard(key, health[key] || {}))
    .join('');

  const sync = data.synchronization || {};
  document.getElementById('mon-sync-cards').innerHTML = [
    monMetricCard(sync.total_today, 'Total Sync Today'),
    monMetricCard(sync.successful, 'Successful Sync', 'ok'),
    monMetricCard(sync.failed, 'Failed Sync', sync.failed > 0 ? 'danger' : 'ok'),
    monMetricCard(sync.partial, 'Partial Sync', sync.partial > 0 ? 'warn' : 'ok'),
    monMetricCard(sync.running, 'Running Sync'),
    monMetricCard(sync.queued, 'Queued Sync', sync.queued > 20 ? 'warn' : 'ok'),
    monMetricCard(sync.average_sync_time_seconds != null ? `${sync.average_sync_time_seconds}s` : '—', 'Average Sync Time'),
    monMetricCard(sync.longest_sync_seconds != null ? `${sync.longest_sync_seconds}s` : '—', 'Longest Sync'),
    monMetricCard(sync.sync_per_minute, 'Sync Per Minute'),
    monMetricCard(sync.sync_per_hour, 'Sync Per Hour'),
  ].join('');

  const outbox = data.outbox || {};
  document.getElementById('mon-outbox-cards').innerHTML = [
    monMetricCard(outbox.pending, 'Pending Rows', outbox.pending > 50 ? 'warn' : 'ok'),
    monMetricCard(outbox.failed, 'Failed Rows', outbox.failed > 0 ? 'danger' : 'ok'),
    monMetricCard(outbox.retry_queue, 'Retry Queue', outbox.retry_queue > 0 ? 'warn' : 'ok'),
    monMetricCard(outbox.dead_queue, 'Dead Queue', outbox.dead_queue > 0 ? 'danger' : 'ok'),
    monMetricCard(outbox.average_retry_count ?? '—', 'Average Retry Count'),
    monMetricCard(outbox.oldest_pending_at ? formatDate(outbox.oldest_pending_at) : '—', 'Oldest Pending Row'),
    monMetricCard(outbox.top_failed_entity?.entity_type || '—', 'Top Failed Entity', 'warn', outbox.top_failed_entity ? `${outbox.top_failed_entity.count} مرة` : ''),
    monMetricCard(outbox.top_failure_reason?.reason || '—', 'Top Failure Reason', 'danger', outbox.top_failure_reason ? `${outbox.top_failure_reason.count} مرة` : ''),
  ].join('');

  const errors = data.errors || {};
  const errorLabels = {
    http_422: 'HTTP 422',
    http_401: 'HTTP 401',
    http_403: 'HTTP 403',
    http_500: 'HTTP 500',
    sqlite_busy: 'SQLite Busy',
    timeout: 'Timeout',
    organization_mismatch: 'Organization Mismatch',
    tenant_bind_failure: 'Tenant Bind Failure',
    cursor_reset: 'Cursor Reset',
    pull_deferred: 'Pull Deferred',
    global_sync_lock_busy: 'Global Sync Lock Busy',
  };
  document.getElementById('mon-error-cards').innerHTML = Object.keys(errorLabels).map((key) => {
    const count = Number(errors[key] || 0);
    return monMetricCard(count, errorLabels[key], count > 0 ? 'danger' : 'ok');
  }).join('');

  const perf = data.performance || {};
  document.getElementById('mon-perf-cards').innerHTML = [
    monMetricCard(perf.average_push_duration_seconds != null ? `${perf.average_push_duration_seconds}s` : '—', 'Average Push Duration'),
    monMetricCard(perf.average_pull_duration_seconds != null ? `${perf.average_pull_duration_seconds}s` : '—', 'Average Pull Duration'),
    monMetricCard(perf.average_api_response_seconds != null ? `${perf.average_api_response_seconds}s` : '—', 'Average API Response'),
    monMetricCard(perf.average_sqlite_transaction_seconds ?? '—', 'Average SQLite Transaction'),
    monMetricCard(perf.average_queue_processing_seconds != null ? `${perf.average_queue_processing_seconds}s` : '—', 'Average Queue Processing'),
    monMetricCard(perf.average_upload_speed ?? '—', 'Average Upload Speed'),
    monMetricCard(perf.average_download_speed ?? '—', 'Average Download Speed'),
    monMetricCard(perf.slowest_organization?.name || '—', 'Slowest Organization', 'warn', perf.slowest_organization?.avg_seconds != null ? `${perf.slowest_organization.avg_seconds}s` : ''),
    monMetricCard(perf.slowest_device?.name || '—', 'Slowest Device', 'warn', perf.slowest_device?.avg_seconds != null ? `${perf.slowest_device.avg_seconds}s` : ''),
  ].join('');

  const security = data.security || {};
  document.getElementById('mon-security-cards').innerHTML = [
    monMetricCard(security.failed_login, 'Failed Login', security.failed_login > 0 ? 'danger' : 'ok'),
    monMetricCard(security.organization_mismatch, 'Organization Mismatch', security.organization_mismatch > 0 ? 'danger' : 'ok'),
    monMetricCard(security.security_events, 'Security Events', security.security_events > 0 ? 'warn' : 'ok'),
    monMetricCard(security.unauthorized_requests, 'Unauthorized Requests', security.unauthorized_requests > 0 ? 'danger' : 'ok'),
    monMetricCard(security.device_revocations, 'Device Revocations'),
    monMetricCard(security.token_validation_errors, 'Token Validation Errors', security.token_validation_errors > 0 ? 'danger' : 'ok'),
    monMetricCard(security.jwt_errors, 'JWT Errors', security.jwt_errors > 0 ? 'danger' : 'ok'),
  ].join('');

  const charts = data.charts || {};
  const points = charts.points || [];
  document.getElementById('mon-charts').innerHTML = `
    <div class="mon-chart-card"><h3>Sync Success Rate</h3>${monSparkline(points, 'success_rate', '#10B981')}</div>
    <div class="mon-chart-card"><h3>Sync Failure Rate</h3>${monSparkline(points, 'failure_rate', '#EF4444')}</div>
    <div class="mon-chart-card"><h3>Average Sync Time</h3>${monSparkline(points, 'avg_seconds', '#5B5CEB')}</div>
    <div class="mon-chart-card"><h3>Outbox Size</h3>${monSparkline(points, 'pending', '#F59E0B')}</div>
    <div class="mon-chart-card"><h3>Organizations Online</h3><div class="kpi-value" style="font-size:42px;margin-top:18px">${escapeHtml(String(charts.organizations_online ?? 0))}</div><div class="mon-card-meta">أونلاين خلال 15 دقيقة</div></div>
    <div class="mon-chart-card"><h3>API Response Time</h3>${monSparkline(points, 'avg_seconds', '#3B82F6')}</div>
    <div class="mon-chart-card" style="grid-column:1/-1"><h3>Errors Timeline</h3>${monBars(points, 'success', 'failure')}</div>
  `;

  const orgs = data.organizations || [];
  const tbody = document.getElementById('mon-orgs-tbody');
  if (!orgs.length) {
    tbody.innerHTML = emptyStateRow(8, 'لا مؤسسات', '▣');
  } else {
    tbody.innerHTML = orgs.map((o) => `<tr>
      <td>${escapeHtml(o.organization_name || o.organization_id || '—')}</td>
      <td>${formatDate(o.last_sync)}</td>
      <td>${escapeHtml(String(o.online_devices ?? 0))}</td>
      <td>${escapeHtml(String(o.offline_devices ?? 0))}</td>
      <td>${escapeHtml(String(o.failed_sync_count ?? 0))}</td>
      <td>${escapeHtml(String(o.pending_outbox ?? 0))}</td>
      <td>${o.average_sync_time_seconds != null ? `${escapeHtml(String(o.average_sync_time_seconds))}s` : '—'}</td>
      <td>${escapeHtml(o.subscription_status || '—')}</td>
    </tr>`).join('');
  }

  if (!silent) scheduleMonAutoRefresh();
}

function bindCompanyDetailActions() {
  document.getElementById('company-detail-view')?.querySelectorAll('[data-copy]').forEach((btn) => {
    btn.addEventListener('click', () => {
      navigator.clipboard.writeText(btn.dataset.copy).then(() => showToast('تم النسخ', 'success'));
    });
  });

  document.getElementById('cc-quick-actions')?.querySelectorAll('[data-cc-action]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const action = btn.dataset.ccAction;
      if (action === 'welcome') document.getElementById('welcome-card')?.click();
      if (action === 'plan') document.getElementById('detail-plan')?.focus();
      if (action === 'suspend') document.getElementById('suspend-company')?.click();
      if (action === 'activate') document.getElementById('activate-company')?.click();
      if (action === 'close') document.getElementById('close-company')?.click();
    });
  });

  document.getElementById('save-plan')?.addEventListener('click', async () => {
    try {
      await api(`/companies/${selectedCompanyId}/subscription`, {
        method: 'PATCH',
        body: JSON.stringify({ plan_code: document.getElementById('detail-plan').value }),
      });
      showToast('تم تحديث الخطة', 'success');
      await openCompany(selectedCompanyId);
    } catch (error) { showToast(error.message, 'error'); }
  });

  document.getElementById('suspend-company')?.addEventListener('click', async () => {
    if (!confirm('تعليق هذا المتجر؟')) return;
    try {
      await api(`/companies/${selectedCompanyId}/status`, { method: 'PATCH', body: JSON.stringify({ status: 'suspended' }) });
      showToast('تم التعليق', 'success');
      await openCompany(selectedCompanyId);
    } catch (error) { showToast(error.message, 'error'); }
  });

  document.getElementById('activate-company')?.addEventListener('click', async () => {
    try {
      await api(`/companies/${selectedCompanyId}/status`, { method: 'PATCH', body: JSON.stringify({ status: 'active' }) });
      showToast('تم التفعيل', 'success');
      await openCompany(selectedCompanyId);
    } catch (error) { showToast(error.message, 'error'); }
  });

  document.getElementById('close-company')?.addEventListener('click', () => {
    const name = selectedCompany?.name || '';
    openModal(
      'إغلاق المتجر',
      `<p>سيتم إغلاق المتجر <strong>${escapeHtml(name)}</strong> ولن يتمكن من المزامنة.</p>
       <p class="muted">يمكن إعادة تفعيله لاحقاً. للحذف النهائي استخدم «حذف المتجر».</p>`,
      [
        { label: 'إلغاء', className: 'btn-ghost', onClick: closeModal },
        {
          label: 'تأكيد الإغلاق',
          className: 'btn-danger',
          onClick: async () => {
            try {
              await api(`/companies/${selectedCompanyId}/status`, {
                method: 'PATCH',
                body: JSON.stringify({ status: 'closed' }),
              });
              closeModal();
              showToast('تم إغلاق المتجر', 'success');
              await openCompany(selectedCompanyId);
            } catch (error) {
              showToast(error.message, 'error');
            }
          },
        },
      ],
    );
  });

  document.getElementById('delete-company')?.addEventListener('click', () => {
    const name = selectedCompany?.name || '';
    openModal(
      'حذف المتجر نهائياً',
      `<p><strong>تحذير:</strong> حذف نهائي وغير قابل للاسترجاع لكل بيانات المتجر على السحابة.</p>
       <p>اكتب اسم المتجر للتأكيد: <code>${escapeHtml(name)}</code></p>
       <label class="field">
         <span>اسم المتجر</span>
         <input id="delete-confirm-name" type="text" autocomplete="off" placeholder="${escapeHtml(name)}">
       </label>
       <label class="field">
         <span>اكتب <code>DELETE</code> للتأكيد الثاني</span>
         <input id="delete-confirm-word" type="text" autocomplete="off" placeholder="DELETE" dir="ltr">
       </label>`,
      [
        { label: 'إلغاء', className: 'btn-ghost', onClick: closeModal },
        {
          label: 'حذف نهائي',
          className: 'btn-danger',
          onClick: async () => {
            const confirmName = document.getElementById('delete-confirm-name')?.value?.trim() || '';
            const confirmWord = document.getElementById('delete-confirm-word')?.value?.trim() || '';
            if (confirmName.toLowerCase() !== String(name).toLowerCase()) {
              showToast('اسم المتجر غير مطابق', 'error');
              return;
            }
            if (confirmWord.toUpperCase() !== 'DELETE') {
              showToast('اكتب DELETE للتأكيد', 'error');
              return;
            }
            try {
              await api(`/companies/${selectedCompanyId}`, {
                method: 'DELETE',
                body: JSON.stringify({
                  confirm_name: confirmName,
                  confirm_delete: 'delete',
                }),
              });
              closeModal();
              showToast('تم حذف المتجر', 'success');
              setView('companies');
            } catch (error) {
              showToast(error.message, 'error');
            }
          },
        },
      ],
    );
  });

  document.getElementById('welcome-card')?.addEventListener('click', async () => {
    try {
      const data = await api(`/companies/${selectedCompanyId}/welcome-card`);
      const el = document.getElementById('detail-welcome');
      el.textContent = data.welcome_card;
      el.classList.remove('hidden');
      lastWelcomeCard = data.welcome_card;
    } catch (error) { showToast(error.message, 'error'); }
  });

  document.getElementById('reset-password')?.addEventListener('click', async () => {
    const password = document.getElementById('new-owner-password').value;
    if (password.length < 8) { showToast('كلمة المرور 8 أحرف على الأقل', 'error'); return; }
    if (!confirm('إعادة تعيين كلمة المرور؟')) return;
    try {
      await api(`/companies/${selectedCompanyId}/reset-password`, { method: 'POST', body: JSON.stringify({ password }) });
      document.getElementById('new-owner-password').value = '';
      showToast('تم التحديث', 'success');
    } catch (error) { showToast(error.message, 'error'); }
  });

  document.getElementById('extend-subscription')?.addEventListener('click', async () => {
    const days = Number(document.getElementById('extend-days')?.value || 0);
    if (days < 1) { showToast('أدخل عدد أيام صحيح', 'error'); return; }
    try {
      await api(`/companies/${selectedCompanyId}/subscription/extend`, { method: 'PATCH', body: JSON.stringify({ days }) });
      showToast('تم التمديد', 'success');
      await openCompany(selectedCompanyId);
    } catch (error) { showToast(error.message, 'error'); }
  });
}

async function loadPlans() {
  const data = await api('/plans');
  plansCache = data.plans || [];
  createPlan.innerHTML = planOptionsHtml('business');
  if (createPlan.querySelector('option[value="business"]')) createPlan.value = 'business';
  const voucherPlan = document.getElementById('voucher-plan');
  if (voucherPlan) {
    voucherPlan.innerHTML = planOptionsHtml('business');
    if (voucherPlan.querySelector('option[value="business"]')) voucherPlan.value = 'business';
  }
}

loginForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  loginError.classList.add('hidden');
  const submitBtn = document.getElementById('login-submit') || loginForm.querySelector('[type="submit"]');
  setButtonBusy(submitBtn, true);
  try {
    const data = await api('/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        email: document.getElementById('login-email').value.trim(),
        password: document.getElementById('login-password').value,
      }),
    });
    setToken(data.access_token);
    adminEmailEl.textContent = data.admin?.email || '';
    showMain();
    await withViewLoading(() => Promise.all([loadDashboard(), loadPlans()]));
  } catch (error) {
    loginError.textContent = error.message || 'فشل تسجيل الدخول';
    loginError.classList.remove('hidden');
    document.getElementById('login-password')?.focus();
  } finally {
    setButtonBusy(submitBtn, false);
  }
});

document.getElementById('logout-btn').addEventListener('click', async () => {
  const token = getToken();
  if (token) {
    try {
      await api('/auth/logout', { method: 'POST', body: JSON.stringify({}) });
    } catch (error) {
      showToast(error.message || 'تعذّر إبطال الجلسة على الخادم', 'warning');
    }
  }
  setToken(null);
  showLogin();
  document.getElementById('login-email')?.focus();
});

document.getElementById('refresh-dashboard')?.addEventListener('click', (event) => {
  const btn = event.currentTarget;
  setButtonBusy(btn, true);
  withViewLoading(loadDashboard)
    .catch((e) => showToast(e.message, 'error'))
    .finally(() => setButtonBusy(btn, false));
});

document.getElementById('refresh-companies').addEventListener('click', (event) => {
  const btn = event.currentTarget;
  setButtonBusy(btn, true);
  withViewLoading(loadCompanies)
    .catch((e) => showToast(e.message, 'error'))
    .finally(() => setButtonBusy(btn, false));
});

document.getElementById('stores-toolbar-refresh')?.addEventListener('click', (event) => {
  const btn = event.currentTarget;
  setButtonBusy(btn, true);
  withViewLoading(loadCompanies)
    .catch((e) => showToast(e.message, 'error'))
    .finally(() => setButtonBusy(btn, false));
});

document.getElementById('stores-goto-create')?.addEventListener('click', () => {
  setView('dashboard');
  window.setTimeout(() => {
    document.getElementById('create-store')?.focus();
    document.getElementById('create-form')?.scrollIntoView({ block: 'center', behavior: 'smooth' });
  }, 120);
});

document.getElementById('stores-status-filters')?.addEventListener('click', (event) => {
  const chip = event.target.closest('[data-status-filter]');
  if (!chip) return;
  companiesStatusFilter = chip.dataset.statusFilter || 'all';
  document.querySelectorAll('#stores-status-filters .stores-filter-chip').forEach((btn) => {
    const active = btn === chip;
    btn.classList.toggle('active', active);
    btn.setAttribute('aria-pressed', active ? 'true' : 'false');
  });
  renderCompaniesRows(companiesCache);
});

document.getElementById('refresh-sync').addEventListener('click', (event) => {
  const btn = event.currentTarget;
  setButtonBusy(btn, true);
  withViewLoading(loadSyncDashboard)
    .catch((e) => showToast(e.message, 'error'))
    .finally(() => setButtonBusy(btn, false));
});

document.getElementById('refresh-observability').addEventListener('click', (event) => {
  const btn = event.currentTarget;
  setButtonBusy(btn, true);
  withViewLoading(loadObservability)
    .catch((e) => showToast(e.message, 'error'))
    .finally(() => setButtonBusy(btn, false));
});

document.getElementById('refresh-monitoring')?.addEventListener('click', (event) => {
  const btn = event.currentTarget;
  setButtonBusy(btn, true);
  withViewLoading(() => loadMonitoring())
    .catch((e) => showToast(e.message, 'error'))
    .finally(() => setButtonBusy(btn, false));
});

document.getElementById('mon-filter-form')?.addEventListener('submit', (event) => {
  event.preventDefault();
  withViewLoading(() => loadMonitoring()).catch((e) => showToast(e.message, 'error'));
});

document.getElementById('mon-filter-reset')?.addEventListener('click', () => {
  ['mon-filter-org', 'mon-filter-branch', 'mon-filter-device', 'mon-filter-from', 'mon-filter-to', 'mon-filter-type'].forEach((id) => {
    const el = document.getElementById(id);
    if (el) el.value = '';
  });
  const status = document.getElementById('mon-filter-status');
  if (status) status.value = '';
  withViewLoading(() => loadMonitoring()).catch((e) => showToast(e.message, 'error'));
});

document.getElementById('mon-auto-refresh')?.addEventListener('change', () => {
  scheduleMonAutoRefresh();
});

let auditLogOffset = 0;
const AUDIT_PAGE_SIZE = 50;
let auditLogTotal = 0;
let auditLogRows = [];

function auditLogFilterParams() {
  const params = new URLSearchParams();
  const map = {
    q: 'auditlog-q',
    date_from: 'auditlog-from',
    date_to: 'auditlog-to',
    organization_id: 'auditlog-org',
    branch_id: 'auditlog-branch',
    user_id: 'auditlog-user',
    device_id: 'auditlog-device',
    entity: 'auditlog-entity',
    action: 'auditlog-action',
    status: 'auditlog-status',
    severity: 'auditlog-severity',
    error_code: 'auditlog-error',
  };
  Object.entries(map).forEach(([key, id]) => {
    const val = document.getElementById(id)?.value?.trim();
    if (val) params.set(key, val);
  });
  const sort = (document.getElementById('auditlog-sort')?.value || 'created_at:desc').split(':');
  params.set('sort_by', sort[0] || 'created_at');
  params.set('sort_dir', sort[1] || 'desc');
  params.set('limit', String(AUDIT_PAGE_SIZE));
  params.set('offset', String(auditLogOffset));
  return params;
}

function auditSeverityClass(severity) {
  if (severity === 'critical' || severity === 'error') return 'danger';
  if (severity === 'warning') return 'warning';
  return 'healthy';
}

function renderAuditLogVirtualRows(rows) {
  const tbody = document.getElementById('auditlog-tbody');
  if (!tbody) return;
  if (!rows.length) {
    tbody.innerHTML = emptyStateRow(8, 'لا أحداث تدقيق', '☰');
    return;
  }
  // Windowed render of current page (virtual scrolling within page)
  const windowSize = 40;
  const visible = rows.slice(0, windowSize);
  tbody.innerHTML = visible.map((row) => `<tr class="audit-row" data-audit-id="${escapeHtml(row.id)}" tabindex="0" role="button">
    <td>${escapeHtml(row.timestamp_utc || '—')}</td>
    <td><code>${escapeHtml(row.action || '—')}</code></td>
    <td><span class="status-pill ${escapeHtml(row.status === 'failure' ? 'danger' : (row.status === 'partial' ? 'warning' : 'healthy'))}">${escapeHtml(row.status || '—')}</span></td>
    <td><span class="status-pill ${auditSeverityClass(row.severity)}">${escapeHtml(row.severity || '—')}</span></td>
    <td dir="ltr">${escapeHtml(row.organization_id || '—')}</td>
    <td>${escapeHtml(row.user_name || row.user_id || '—')}</td>
    <td>${escapeHtml([row.entity, row.entity_id].filter(Boolean).join(' · ') || '—')}</td>
    <td dir="ltr">${escapeHtml(row.ip_address || '—')}</td>
  </tr>`).join('');
  if (rows.length > windowSize) {
    tbody.insertAdjacentHTML('beforeend', `<tr class="audit-more-row"><td colspan="8" class="muted">عرض ${windowSize} من ${rows.length} في الصفحة — استخدم التصفح للبقية</td></tr>`);
  }
}

async function openAuditDetail(id) {
  try {
    const data = await api(`/audit-events/${id}`);
    const e = data.event || {};
    const jsonBlock = (obj) => `<pre class="audit-json">${escapeHtml(JSON.stringify(obj ?? {}, null, 2))}</pre>`;
    openModal(
      'تفاصيل Audit Event',
      `<div class="audit-detail">
        <div class="audit-detail-grid">
          <div><span class="muted">Audit ID</span><div dir="ltr">${escapeHtml(e.id)}</div></div>
          <div><span class="muted">Timestamp UTC</span><div dir="ltr">${escapeHtml(e.timestamp_utc || '—')}</div></div>
          <div><span class="muted">Action</span><div><code>${escapeHtml(e.action || '—')}</code></div></div>
          <div><span class="muted">Status / Severity</span><div>${escapeHtml(e.status || '—')} · ${escapeHtml(e.severity || '—')}</div></div>
          <div><span class="muted">Organization</span><div dir="ltr">${escapeHtml(e.organization_id || '—')}</div></div>
          <div><span class="muted">Branch</span><div dir="ltr">${escapeHtml(e.branch_id || '—')}</div></div>
          <div><span class="muted">User</span><div>${escapeHtml(e.user_name || '—')} <span class="muted" dir="ltr">${escapeHtml(e.user_id || '')}</span></div></div>
          <div><span class="muted">Role</span><div>${escapeHtml(e.role || '—')}</div></div>
          <div><span class="muted">Device</span><div dir="ltr">${escapeHtml(e.device_id || '—')}</div></div>
          <div><span class="muted">Installation</span><div dir="ltr">${escapeHtml(e.installation_id || '—')}</div></div>
          <div><span class="muted">Session</span><div dir="ltr">${escapeHtml(e.session_id || '—')}</div></div>
          <div><span class="muted">Request ID</span><div dir="ltr">${escapeHtml(e.request_id || '—')}</div></div>
          <div><span class="muted">Transaction UUID</span><div dir="ltr">${escapeHtml(e.transaction_uuid || '—')}</div></div>
          <div><span class="muted">Correlation ID</span><div dir="ltr">${escapeHtml(e.correlation_id || '—')}</div></div>
          <div><span class="muted">Entity</span><div>${escapeHtml(e.entity || '—')} / ${escapeHtml(e.entity_id || '—')}</div></div>
          <div><span class="muted">IP / UA</span><div dir="ltr">${escapeHtml(e.ip_address || '—')}<br><span class="muted">${escapeHtml(e.user_agent || '')}</span></div></div>
          <div><span class="muted">Platform / Version</span><div>${escapeHtml(e.platform || '—')} · ${escapeHtml(e.application_version || '—')}</div></div>
          <div><span class="muted">Trigger / Duration</span><div>${escapeHtml(e.trigger || '—')} · ${escapeHtml(String(e.duration ?? '—'))} ms</div></div>
          <div><span class="muted">Reason</span><div>${escapeHtml(e.reason || '—')}</div></div>
          <div><span class="muted">Error</span><div>${escapeHtml(e.error_code || '—')}: ${escapeHtml(e.error_message || '—')}</div></div>
        </div>
        <h4>Request</h4>${jsonBlock(e.request)}
        <h4>Response</h4>${jsonBlock(e.response)}
        <h4>Metadata</h4>${jsonBlock(e.metadata)}
        <h4>Stack Trace</h4><pre class="audit-json">${escapeHtml(e.stack_trace || '—')}</pre>
        <h4>Full JSON</h4>${jsonBlock(e)}
      </div>`,
      [{ label: 'إغلاق', className: 'btn-primary', onClick: closeModal }],
    );
  } catch (error) {
    showToast(error.message, 'error');
  }
}

async function loadAuditLogPage() {
  const params = auditLogFilterParams();
  const [list, alerts, retention] = await Promise.all([
    api(`/audit-events?${params.toString()}`),
    api('/audit-events/alerts').catch(() => ({ alerts: [] })),
    api('/audit-events/retention').catch(() => null),
  ]);
  auditLogRows = list.entries || [];
  auditLogTotal = list.total || 0;
  renderAuditLogVirtualRows(auditLogRows);

  const meta = document.getElementById('auditlog-meta');
  if (meta) meta.textContent = `عرض ${auditLogRows.length} من ${auditLogTotal}`;

  const page = Math.floor(auditLogOffset / AUDIT_PAGE_SIZE) + 1;
  const pages = Math.max(1, Math.ceil(auditLogTotal / AUDIT_PAGE_SIZE));
  const pageLabel = document.getElementById('auditlog-page-label');
  if (pageLabel) pageLabel.textContent = `صفحة ${page} / ${pages}`;
  document.getElementById('auditlog-prev').disabled = auditLogOffset <= 0;
  document.getElementById('auditlog-next').disabled = auditLogOffset + AUDIT_PAGE_SIZE >= auditLogTotal;

  const banner = document.getElementById('auditlog-alert-banner');
  const alertList = alerts.alerts || [];
  if (banner) {
    if (!alertList.length) {
      banner.classList.add('hidden');
      banner.textContent = '';
    } else {
      banner.classList.remove('hidden');
      banner.innerHTML = alertList.map((a) => `⚠ ${escapeHtml(a.message)} — ${escapeHtml(String(a.count))}/${escapeHtml(String(a.threshold))}`).join(' · ');
    }
  }

  if (retention) {
    const daysEl = document.getElementById('auditlog-retention-days');
    if (daysEl && retention.days) daysEl.value = String(retention.days);
    const rMeta = document.getElementById('auditlog-retention-meta');
    if (rMeta) {
      rMeta.textContent = `الاحتفاظ: ${retention.days} يوم · الأرشفة: ${retention.archive_enabled ? 'مفعّلة' : 'متوقفة'}`;
    }
  }
}

async function downloadAuditExport(format) {
  const params = auditLogFilterParams();
  params.delete('limit');
  params.delete('offset');
  params.set('format', format);
  const token = getToken();
  const response = await fetch(`${API_BASE}/audit-events/export?${params.toString()}`, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
  if (!response.ok) {
    throw new Error(`Export failed HTTP ${response.status}`);
  }
  const blob = await response.blob();
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `miza_audit.${format === 'excel' ? 'xls' : format}`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

document.getElementById('refresh-auditlog')?.addEventListener('click', (event) => {
  const btn = event.currentTarget;
  setButtonBusy(btn, true);
  withViewLoading(() => loadAuditLogPage())
    .catch((e) => showToast(e.message, 'error'))
    .finally(() => setButtonBusy(btn, false));
});

document.getElementById('auditlog-filter-form')?.addEventListener('submit', (event) => {
  event.preventDefault();
  auditLogOffset = 0;
  withViewLoading(() => loadAuditLogPage()).catch((e) => showToast(e.message, 'error'));
});

document.getElementById('auditlog-filter-reset')?.addEventListener('click', () => {
  ['auditlog-q', 'auditlog-from', 'auditlog-to', 'auditlog-org', 'auditlog-branch', 'auditlog-user', 'auditlog-device', 'auditlog-entity', 'auditlog-action', 'auditlog-error'].forEach((id) => {
    const el = document.getElementById(id);
    if (el) el.value = '';
  });
  ['auditlog-status', 'auditlog-severity'].forEach((id) => {
    const el = document.getElementById(id);
    if (el) el.value = '';
  });
  auditLogOffset = 0;
  withViewLoading(() => loadAuditLogPage()).catch((e) => showToast(e.message, 'error'));
});

document.getElementById('auditlog-sort')?.addEventListener('change', () => {
  auditLogOffset = 0;
  withViewLoading(() => loadAuditLogPage()).catch((e) => showToast(e.message, 'error'));
});

document.getElementById('auditlog-prev')?.addEventListener('click', () => {
  auditLogOffset = Math.max(0, auditLogOffset - AUDIT_PAGE_SIZE);
  withViewLoading(() => loadAuditLogPage()).catch((e) => showToast(e.message, 'error'));
});

document.getElementById('auditlog-next')?.addEventListener('click', () => {
  auditLogOffset += AUDIT_PAGE_SIZE;
  withViewLoading(() => loadAuditLogPage()).catch((e) => showToast(e.message, 'error'));
});

document.getElementById('auditlog-tbody')?.addEventListener('click', (event) => {
  const row = event.target.closest('[data-audit-id]');
  if (!row) return;
  openAuditDetail(row.dataset.auditId);
});

document.getElementById('auditlog-tbody')?.addEventListener('keydown', (event) => {
  if (event.key !== 'Enter' && event.key !== ' ') return;
  const row = event.target.closest('[data-audit-id]');
  if (!row) return;
  event.preventDefault();
  openAuditDetail(row.dataset.auditId);
});

document.querySelectorAll('[data-audit-export]').forEach((btn) => {
  btn.addEventListener('click', () => {
    downloadAuditExport(btn.dataset.auditExport)
      .then(() => showToast('تم التصدير', 'success'))
      .catch((e) => showToast(e.message, 'error'));
  });
});

document.getElementById('auditlog-retention-save')?.addEventListener('click', async () => {
  try {
    const days = Number(document.getElementById('auditlog-retention-days')?.value || 90);
    await api('/audit-events/retention', {
      method: 'PATCH',
      body: JSON.stringify({ days, archive_enabled: true }),
    });
    showToast('تم حفظ سياسة الاحتفاظ', 'success');
    await loadAuditLogPage();
  } catch (e) {
    showToast(e.message, 'error');
  }
});

document.getElementById('auditlog-retention-run')?.addEventListener('click', async () => {
  if (!confirm('أرشفة السجلات الأقدم من فترة الاحتفاظ؟')) return;
  try {
    const result = await api('/audit-events/retention/run', { method: 'POST', body: JSON.stringify({}) });
    showToast(`تمت أرشفة ${result.archived ?? 0} سجل`, 'success');
    await loadAuditLogPage();
  } catch (e) {
    showToast(e.message, 'error');
  }
});

document.getElementById('voucher-form')?.addEventListener('submit', async (event) => {
  event.preventDefault();
  const submitBtn = event.target.querySelector('[type="submit"]');
  setButtonBusy(submitBtn, true);
  try {
    await api('/vouchers', {
      method: 'POST',
      body: JSON.stringify({
        code: document.getElementById('voucher-code').value.trim().toUpperCase(),
        plan_code: document.getElementById('voucher-plan').value,
        max_uses: Number(document.getElementById('voucher-max-uses').value || 1),
        notes: document.getElementById('voucher-notes').value.trim(),
      }),
    });
    showToast('تم إنشاء الكود', 'success');
    event.target.reset();
    document.getElementById('voucher-max-uses').value = '1';
    if (document.getElementById('voucher-plan').options.length) {
      document.getElementById('voucher-plan').value = 'business';
    }
    await loadDashboard();
  } catch (error) {
    showToast(error.message, 'error');
  } finally {
    setButtonBusy(submitBtn, false);
  }
});

document.getElementById('load-audit').addEventListener('click', (event) => {
  const btn = event.currentTarget;
  setButtonBusy(btn, true);
  loadAuditLogs()
    .catch((e) => showToast(e.message, 'error'))
    .finally(() => setButtonBusy(btn, false));
});

staleDevicesTbody.addEventListener('click', (event) => {
  const button = event.target.closest('[data-company-id]');
  if (!button) return;
  openCompany(button.dataset.companyId).catch((e) => showToast(e.message, 'error'));
});

companySearch.addEventListener('input', () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => loadCompanies().catch((e) => showToast(e.message, 'error')), 350);
});

document.getElementById('back-to-list').addEventListener('click', () => {
  setView('companies');
});

document.getElementById('cc-refresh')?.addEventListener('click', (event) => {
  if (!selectedCompanyId) return;
  const btn = event.currentTarget;
  setButtonBusy(btn, true);
  openCompany(selectedCompanyId)
    .catch((e) => showToast(e.message, 'error'))
    .finally(() => setButtonBusy(btn, false));
});

document.querySelectorAll('.nav-btn').forEach((btn) => {
  btn.addEventListener('click', () => setView(btn.dataset.view));
});

companiesTbody.addEventListener('click', (event) => {
  const button = event.target.closest('[data-company-id]');
  if (!button) return;
  openCompany(button.dataset.companyId).catch((e) => showToast(e.message, 'error'));
});

devicesTbody.addEventListener('click', async (event) => {
  const button = event.target.closest('[data-revoke]');
  if (!button || !selectedCompanyId) return;
  if (!confirm('إلغاء هذا الجهاز؟')) return;
  setButtonBusy(button, true);
  try {
    await api(`/devices/${button.dataset.revoke}/revoke`, { method: 'POST' });
    showToast('تم الإلغاء', 'success');
    await openCompany(selectedCompanyId);
  } catch (error) {
    showToast(error.message, 'error');
    setButtonBusy(button, false);
  }
});

copyWelcomeBtn?.addEventListener('click', () => {
  if (!lastWelcomeCard) return;
  navigator.clipboard.writeText(lastWelcomeCard).then(() => showToast('تم النسخ', 'success'));
});

copySignupWelcomeBtn?.addEventListener('click', () => {
  if (!lastWelcomeCard) return;
  navigator.clipboard.writeText(lastWelcomeCard).then(() => showToast('تم النسخ', 'success'));
});

createForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  createError.classList.add('hidden');
  createResultWrap.classList.add('hidden');
  const submitBtn = createForm.querySelector('[type="submit"]');
  setButtonBusy(submitBtn, true);

  try {
    const data = await api('/companies', {
      method: 'POST',
      body: JSON.stringify({
        store_name: document.getElementById('create-store').value.trim(),
        email: document.getElementById('create-email').value.trim(),
        owner_name: document.getElementById('create-owner').value.trim(),
        password: document.getElementById('create-password').value,
        plan_code: createPlan.value,
      }),
    });
    const tenant = data.tenant;
    showCreateWelcome(tenant.welcome_card || `تم إنشاء ${tenant.store_name}`);
    createForm.reset();
    if (createPlan.options.length) createPlan.value = 'business';
    showToast('تم إنشاء المتجر', 'success');
    await loadDashboard();
  } catch (error) {
    createError.textContent = error.message;
    createError.classList.remove('hidden');
    showToast(error.message, 'error');
  } finally {
    setButtonBusy(submitBtn, false);
  }
});

bootstrap();
