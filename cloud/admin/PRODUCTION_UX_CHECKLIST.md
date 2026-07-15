# Miza Cloud Ops — Production UX Checklist

Visual identity is locked. This checklist tracks **production readiness** only: polish, accessibility, responsive behavior, and consistency. No redesign. No backend/API/business-logic changes.

Last audited: 2026-07-13

---

## Scope

| Area | In scope | Out of scope |
|------|----------|--------------|
| Admin SPA (`cloud/admin/public/`) | Yes | — |
| Layout / spacing / focus / loading | Fix | Redesign |
| Backend, APIs, DB, permissions, routes | — | Do not change |
| Visual identity tokens / brand look | Preserve | Do not restyle brand |

---

## Pages reviewed

- [x] Login
- [x] Dashboard
- [x] Stores (list)
- [x] Store Command Center (detail)
- [x] Sync monitoring
- [x] Observability / audit
- [x] Modal + toast (global)

---

## Alignment & spacing

| Check | Status | Notes |
|-------|--------|-------|
| Page headers follow Title / Description / Actions | Pass | Unified via identity + UX polish |
| Card internal padding consistent | Pass | 16px radius / soft shadow preserved |
| Section gaps stable across pages | Pass | |
| Table cell padding / header rhythm | Pass | Sticky headers added for long tables |
| No overlapping controls at common widths | Pass | |

---

## Responsive

| Breakpoint | Target | Status | Fixes applied |
|------------|--------|--------|---------------|
| Desktop ≥ 1200px | Full layout | Pass | — |
| Laptop ~ 1100px | Single column where needed | Pass | Existing media queries |
| Tablet ≤ 900px | Sidebar stacks; logout visible | **Fixed** | Logout was `display: none` — restored |
| Mobile ≤ 520px | Forms / filters / action groups wrap | Pass | Filter row + action buttons wrap |

Manual verify after deploy:

- [ ] Login card readable on 360px width
- [ ] Stores table scrolls horizontally without clipping actions
- [ ] Command Center side column stacks under main
- [ ] Modals fit within viewport height (scroll body)

---

## Keyboard & focus

| Check | Status | Notes |
|-------|--------|-------|
| Skip link to main content | **Fixed** | `تخطي إلى المحتوى` |
| All buttons keyboard reachable | Pass | Native `<button>` |
| Visible `:focus-visible` rings | **Fixed** | Buttons, nav, chips, inputs |
| Modal Escape closes | **Fixed** | |
| Modal restores focus on close | **Fixed** | |
| Modal focuses first action on open | **Fixed** | |
| Filter chips `aria-pressed` | **Fixed** | |
| Nav `aria-current="page"` | **Fixed** | Including Command Center → Stores |

Manual verify:

- [ ] Tab order Login → fields → submit
- [ ] Tab through sidebar without trap
- [ ] Approve/Reject modal: Tab cycles actions, Escape closes

---

## Loading / empty / error / success

| Check | Status | Notes |
|-------|--------|-------|
| View-level loading indicator | **Fixed** | Spinner on `.main-area.is-loading` |
| Submit / refresh button busy state | **Fixed** | `is-busy` + disabled |
| Empty states present on tables/panels | Pass | Shared empty component |
| Inline form errors (`role="alert"`) | **Fixed** | Login + create store |
| Toast success / error / info | **Fixed** | `aria-live="polite"` |
| No silent failures on refresh | Pass | Errors toast as `error` |

---

## Accessibility

| Check | Status | Notes |
|-------|--------|-------|
| Landmark: `main#main-content` | **Fixed** | |
| Sidebar `aria-label` | **Fixed** | |
| Search inputs labeled | **Fixed** | Stores + audit filters |
| Decorative icons `aria-hidden` | Pass | |
| Secondary text contrast | **Improved** | Muted copy → `#475569` |
| Toast announced to AT | **Fixed** | `role="status"` |
| Modal `aria-labelledby` | **Fixed** | |
| `prefers-reduced-motion` respected | **Fixed** | |

Remaining (manual / optional later):

- [ ] Full WCAG AA contrast audit on warning/success badges
- [ ] Screen-reader pass on Command Center action list
- [ ] Replace native `confirm()` for device revoke with modal (behavior-identical) — optional polish only

---

## Scroll & sticky

| Check | Status | Notes |
|-------|--------|-------|
| Scroll to top on view change | **Fixed** | |
| Body scroll locked while modal open | **Fixed** | `body.modal-open` |
| Sticky table headers in tall wraps | **Fixed** | Desktop; disabled max-height on small screens |
| Horizontal table overflow | Pass | `.table-wrap { overflow: auto }` |

---

## Component consistency

| Component | Status | Notes |
|-----------|--------|-------|
| Buttons (family + sizes) | Pass | Identity preserved; busy polish only |
| Cards | Pass | No redesign |
| Tables | Pass | Sticky + empty + hover preserved |
| Status badges | Pass | Shared status map |
| Forms | Pass | Invalid border + alert styling |
| Dialogs | Pass | Focus + Escape + scroll |
| Icons | Pass | Same circle/size language |

---

## Performance (front-end)

| Check | Status | Notes |
|-------|--------|-------|
| Avoid layout shift on KPI mounts | **Improved** | `min-height` on KPI / summary grids |
| Remove inline styles where easy | **Fixed** | Voucher uppercase + LTR cells → classes |
| Dead CSS mass deletion | Deferred | Large legacy page CSS kept to avoid regressions; prefer incremental cleanup |
| Duplicate CSS | Acceptable | Identity + UX layers override intentionally |
| Unnecessary DOM | Pass | No new feature widgets |

---

## Regression guardrails

Do **not** ship if any of these fail:

1. Logout missing on tablet/mobile
2. Modal cannot be dismissed with Escape or close button
3. Refresh / submit leaves buttons stuck disabled
4. Any API path, route, or permission changed
5. Visual identity tokens swapped or pages redesigned

---

## Files touched this sprint

| File | Role |
|------|------|
| `public/miza-ux-polish.css` | UX / a11y / responsive polish layer |
| `public/index.html` | Landmarks, labels, modal/toast a11y |
| `public/admin.js` | Loading, toast types, modal focus, Escape |
| `PRODUCTION_UX_CHECKLIST.md` | This document |

Identity files (`admin.css`, `miza-identity.css`) were not redesigned; UX layer loads last.

---

## Sign-off

| Role | Name | Date | Result |
|------|------|------|--------|
| UX polish | — | 2026-07-13 | Ready for QA |
| Ops QA | | | |
| Production deploy | | | |
