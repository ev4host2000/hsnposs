# خارطة تطوير لوحة العمليات — Miza Cloud Ops

> **الحالة:** RC1 Approved · Code Freeze (2026-07-14)  
> **المرجع العام:** [`docs/ROADMAP.md`](../../docs/ROADMAP.md)

---

## المرحلة 1 — دعم Beta ✅ (منجزة)

| الميزة | API | الواجهة |
|--------|-----|---------|
| بحث متاجر | `GET /companies?q=` | حقل بحث |
| بطاقة ترحيب | `welcome_card` + `GET .../welcome-card` | نسخ |
| تعديل خطة | `PATCH .../subscription` | قائمة في التفاصيل |
| تعليق/تفعيل/إغلاق | `PATCH .../status` | أزرار |
| حذف متجر نهائي | `DELETE .../companies/{id}` | تأكيد مزدوج |
| إعادة تعيين كلمة مرور | `POST .../reset-password` | حقل + زر |
| نسخ IDs | — | أزرار نسخ |

---

## المرحلة 2 — مراقبة المزامنة ✅ (منجزة)

| الميزة | API | الواجهة |
|--------|-----|---------|
| نظرة عامة | `GET /sync/overview` | تبويب «المزامنة» |
| صحة متجر | `GET /companies/{id}/sync-health` | بطاقة في التفاصيل |
| أخطاء sync | `GET /sync/failures` | جدول |
| تعارضات | `GET /sync/conflicts` | جدول |
| أجهزة غائبة (+24h) | ضمن overview | جدول + علامة في الأجهزة |

---

## المرحلة 3 — Observability ✅ (منجزة)

| الميزة | API | الواجهة |
|--------|-----|---------|
| نظرة عامة | `GET /observability/overview` | تبويب «النظام» |
| صحة DB + تخزين + سجلات | ضمن overview | بطاقة بنية تحتية |
| تنبيهات | ضمن overview | اشتراك منتهٍ، queue، أجهزة غائبة |
| Audit log | `GET /audit-logs` | جدول + فلاتر |

---

## المرحلة 4 — أمان وتوسع Ops ⏭️ (مؤجّلة — P3)

| الميزة | الحالة | المعرّف |
|--------|--------|---------|
| مستخدمي Ops متعددين + أدوار | مؤجّل | P3-03 |
| 2FA | مؤجّل | P3-04 |
| Kill switch (إيقاف sync لمتجر/جهاز) | مؤجّل | P3-05 |
| سجل نشاط Ops (من فعل ماذا) | مؤجّل | P3 |

**ملاحظة:** P1-02 أغلق فجوة **إبطال توكن Ops خادمياً** (`POST /auth/logout` + `platform_admin_tokens`). المرحلة 4 تبقى لتوسيع الفريق وليس لإغلاق RC1.

---

## المرحلة 5 — تسجيل ذاتي + لوحة المالك ✅ (منجزة)

| الميزة | API | الواجهة |
|--------|-----|---------|
| طلب Beta عام | `POST /v1/public/beta-signup` | `/owner/signup.html` |
| التحقق من كود | `POST /v1/public/voucher/validate` | (اختياري) |
| مراجعة الطلبات | `GET /signup-requests` + approve/reject | تبويب «طلبات Beta» |
| أكواد الدعوة | `GET/POST /vouchers` | تبويب «أكواد الدعوة» |
| تمديد اشتراك | `PATCH .../subscription/extend` | تفاصيل المتجر |
| لوحة المالك | `/v1/owner/*` | `https://api.mizapos.com/owner/` |

---

## أمان Ops — إنجازات RC1

| القدرة | البند | الحالة |
|--------|-------|--------|
| IP allowlist | P0-03 | ✅ |
| Rate limit login | P1-01 | ✅ |
| Server-side token revocation | P1-02 | ✅ |
| Logout API + SPA | P1-02 | ✅ |

---

## التسلسل

```
[1] دعم Beta ✅ → [2] Sync ✅ → [3] Audit/Metrics ✅ → [4] P3 ⏭️ → [5] Self-service + Owner ✅
                                              ↑
                                    P1-02: Ops token revoke ✅
```

*آخر تحديث: 2026-07-14 — P1-08 مواءمة وثائق.*
