# Miza Cloud — خارطة طريق المشروع (`cloud/`)

> **⚠️ المستند المعتمد للحالة الحالية:** [`docs/ROADMAP.md`](../../docs/ROADMAP.md)  
> **الحالة:** RC1 Approved · Code Freeze (2026-07-14)  
> **هذا الملف:** مرجع تفصيلي لمراحل البناء في `cloud/` — **مُحدَّث ليعكس الإنجاز الفعلي**.

---

## ملخص الحالة (2026-07-14)

| Phase في هذا الملف | الحالة الفعلية |
|--------------------|----------------|
| 1 — التأسيس | ✅ مكتمل |
| 2 — PostgreSQL schema | ✅ مكتمل (migrations 001–020) |
| 3 — Auth & Registration | ✅ مكتمل (جزئياً: self-service register مؤجّل) |
| 4 — License & Settings | ✅ مكتمل (على PostgreSQL) |
| 5 — Sync Engine Flutter | ✅ مكتمل |
| 6 — Pull Master Data | ✅ مكتمل |
| 7 — Push Transactions | ✅ مكتمل |
| 8 — Multi-Branch/Device | ✅ مكتمل |
| 9 — Field Ops migration | ⏳ مؤجّل |
| 10 — Admin & Monitoring | ✅ مكتمل (Ops + Owner Portal) |
| 11 — Production go-live | ✅ `api.mizapos.com` حي |
| 12 — Post-launch | ⏳ مخطط |

**بوابة الإصدار:** P0 (6/6) + P1 (8/8) — [`docs/RC_CERTIFICATION_V2.md`](../../docs/RC_CERTIFICATION_V2.md)

---

## Phase 1 — التأسيس والبنية ✅

- [x] هيكل `cloud/api` · `database` · `deploy` · `admin` · `owner`
- [x] توثيق Architecture في `cloud/docs/`
- [x] `.env.example` / `.env.staging`
- [x] PHP API في `cloud/api`
- [x] Docker Compose (local · staging · test)
- [x] `api.mizapos.com` — DNS · TLS · reverse proxy

---

## Phase 2 — قاعدة البيانات ✅

- [x] DDL كامل — Tenancy · Identity · Auth tokens · Commercial · Master Data · Transactions · Sync · Ops
- [x] Indexes · Foreign Keys · constraints
- [x] Seed · migrations حتى **020** (`platform_admin_tokens`)
- [x] Repository layer → PostgreSQL

---

## Phase 3 — المصادقة والتسجيل ✅

- [x] `POST /auth/login` · refresh · logout · me
- [x] `POST /auth/devices/register` · pairing
- [x] `POST /auth/password/forgot` (+ harden P1-03)
- [x] JWT + scopes + rate limit (P1-01)
- [x] Middleware CORS
- [ ] `POST /auth/companies/register` self-service — *(مؤجّل؛ Beta عبر Ops/Owner signup)*

---

## Phase 4 — API الإعدادات والترخيص ✅

- [x] `GET /health` · subscription status
- [x] Licenses · organization/branch/device settings
- [x] Notifications API
- [ ] ترحيل `drhsn` SQLite → PostgreSQL — *(مؤجّل P3)*

---

## Phase 5–7 — Sync Engine ✅

- [x] `SyncEngine` · outbox · meta · retry
- [x] Pull catalog + partners
- [x] Push transactions (8 أنواع)
- [x] LWW مسودات — [`docs/SYNC_CONFLICT_POLICY.md`](../../docs/SYNC_CONFLICT_POLICY.md)
- [x] Integration tests

---

## Phase 8 — Multi-Branch & Multi-Device ✅

- [x] `user_branch_access` · device sessions
- [x] Admin: list devices · revoke device (P0-01)
- [x] License slots

---

## Phase 9 — Field Ops ⏳

- [ ] ترحيل field-catalog / field-orders / team-users
- [ ] Parallel run + cutover

---

## Phase 10 — Admin Panel & Observability ✅

- [x] Ops Admin SPA — [`cloud/admin/ROADMAP.md`](../admin/ROADMAP.md)
- [x] Audit log · sync monitor · observability
- [x] Platform admin token revocation (P1-02)
- [x] Owner Portal `/owner/`
- [ ] Metrics/alerting متقدم — *(P3)*

---

## Phase 11 — Production ✅

- [x] Staging/production على VPS
- [x] Security: session revocation · Ops allowlist · rate limit
- [x] Runbooks في `docs/runbooks/`
- [x] Beta requirements gate (P0-06)

---

## Phase 12 — ما بعد الإطلاق ⏳

- [ ] Web dashboard موسّع
- [ ] Real-time notifications
- [ ] Multi-currency / integrations
- [ ] Performance partitioning

---

## P2 / P3 (خارج نطاق RC1)

انظر [`docs/PROJECT_STATUS.md`](../../docs/PROJECT_STATUS.md) §5–7.

---

*آخر تحديث: 2026-07-14 — مواءمة P1-08 · لا يُنفَّذ أي بند تلقائياً.*
