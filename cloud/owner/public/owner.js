const API = '/v1/owner';
const TOKEN_KEY = 'miza_owner_token';

const loginView = document.getElementById('login-view');
const mainView = document.getElementById('main-view');
const loginForm = document.getElementById('login-form');
const loginError = document.getElementById('login-error');
const companySelectWrap = document.getElementById('company-select-wrap');
const companySelect = document.getElementById('company-select');
const toast = document.getElementById('toast');

let pendingCompanies = null;

function token() { return localStorage.getItem(TOKEN_KEY); }
function setToken(v) { v ? localStorage.setItem(TOKEN_KEY, v) : localStorage.removeItem(TOKEN_KEY); }

function showToast(msg) {
  toast.textContent = msg;
  toast.classList.remove('hidden');
  setTimeout(() => toast.classList.add('hidden'), 3000);
}

async function api(path, options = {}) {
  const headers = { ...(options.headers || {}) };
  if (options.body !== undefined) headers['Content-Type'] = 'application/json';
  if (token()) headers.Authorization = `Bearer ${token()}`;
  const res = await fetch(`${API}${path}`, { ...options, headers });
  const payload = await res.json().catch(() => ({}));
  if (!res.ok || !payload.ok) throw new Error(payload.error?.message || `HTTP ${res.status}`);
  return payload.data;
}

function formatDate(v) {
  if (!v) return '—';
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? v : d.toLocaleString('ar-SA');
}

function formatMoney(v) {
  return Number(v || 0).toLocaleString('ar-SA', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

async function loadDashboard() {
  const [me, dash, devices] = await Promise.all([
    api('/me'),
    api('/dashboard'),
    api('/devices'),
  ]);
  document.getElementById('company-name').textContent = me.user?.full_name || '';
  document.getElementById('user-name').textContent = me.user?.email || '';
  const s = dash.summary || {};
  document.getElementById('summary-cards').innerHTML = `
    <div class="stat-card"><strong>${formatMoney(s.sales_today_total)}</strong>مبيعات اليوم (${s.sales_today_count || 0})</div>
    <div class="stat-card"><strong>${formatMoney(s.sales_month_total)}</strong>مبيعات الشهر (${s.sales_month_count || 0})</div>
    <div class="stat-card"><strong>${s.products_count || 0}</strong>منتجات</div>
    <div class="stat-card"><strong>${s.active_devices || 0}</strong>أجهزة نشطة</div>
  `;
  const sub = dash.subscription || {};
  document.getElementById('subscription-card').innerHTML = `
    <h3>الاشتراك</h3>
    <p><strong>الخطة:</strong> ${sub.plan_name || sub.plan_code || '—'} (${sub.max_devices || '?'} جهاز)</p>
    <p><strong>ينتهي:</strong> ${formatDate(sub.current_period_end)}</p>
    <p class="muted">Company ID: <code dir="ltr">${me.company_id}</code></p>
  `;
  const tbody = document.getElementById('devices-tbody');
  tbody.innerHTML = '';
  for (const d of devices.devices || []) {
    const tr = document.createElement('tr');
    const revoked = d.revoked_at || d.status === 'revoked';
    tr.innerHTML = `
      <td>${d.device_name}</td><td>${d.platform}</td><td>${d.app_version || '—'}</td>
      <td>${formatDate(d.last_seen_at)}</td>
      <td><span class="badge ${revoked ? 'revoked' : 'active'}">${revoked ? 'ملغى' : 'نشط'}</span></td>`;
    tbody.appendChild(tr);
  }
}

loginForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  loginError.classList.add('hidden');
  const body = {
    email: document.getElementById('email').value.trim(),
    password: document.getElementById('password').value,
  };
  if (companySelectWrap.classList.contains('hidden') === false) {
    body.company_id = companySelect.value;
  }
  try {
    const data = await api('/auth/login', { method: 'POST', body: JSON.stringify(body) });
    if (data.needs_company_selection) {
      pendingCompanies = data.companies;
      companySelect.innerHTML = data.companies.map((c) =>
        `<option value="${c.company_id}">${c.company_name}</option>`).join('');
      companySelectWrap.classList.remove('hidden');
      showToast('اختر المتجر ثم أعد الدخول');
      return;
    }
    setToken(data.access_token);
    loginView.classList.add('hidden');
    mainView.classList.remove('hidden');
    companySelectWrap.classList.add('hidden');
    await loadDashboard();
  } catch (err) {
    loginError.textContent = err.message;
    loginError.classList.remove('hidden');
  }
});

document.getElementById('logout-btn').addEventListener('click', () => {
  setToken(null);
  mainView.classList.add('hidden');
  loginView.classList.remove('hidden');
});

(async () => {
  if (!token()) return;
  try {
    loginView.classList.add('hidden');
    mainView.classList.remove('hidden');
    await loadDashboard();
  } catch {
    setToken(null);
  }
})();
