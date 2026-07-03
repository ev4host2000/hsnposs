<?php
declare(strict_types=1);

/**
 * إنشاء أول حساب مالك من المتصفح (مناسب إذا لم يتوفر SSH — بعد الرفع عبر FTP).
 *
 * 1) أضف في .env سطراً: SETUP_TOKEN=MzPs-setup-change-after-first-login-k9Qm2Vx7Nw4Ry6Lu1
 * 2) افتح: http://mizapos.com/drhsn/setup_once.php
 * 3) بعد النجاح: احذف هذا الملف من الخادم وأزل أو فرّغ SETUP_TOKEN من .env
 */

require __DIR__ . '/includes/config.php';
require __DIR__ . '/includes/db.php';

$config = activation_config();
$h = static function (string $s): string {
    return htmlspecialchars($s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
};

try {
    $pdo = activation_open_db($config['DATABASE_PATH']);
} catch (Throwable $e) {
    http_response_code(500);
    header('Content-Type: text/html; charset=utf-8');
    echo '<!DOCTYPE html><html lang="ar" dir="rtl"><meta charset="utf-8"><title>خطأ</title><body style="font-family:sans-serif;padding:24px">';
    echo '<p>فشل فتح قاعدة البيانات: ' . $h($e->getMessage()) . '</p></body></html>';
    exit;
}

$adminCount = (int) $pdo->query('SELECT COUNT(*) AS c FROM admins')->fetch(PDO::FETCH_ASSOC)['c'];
$setupTokenConfigured = ($config['SETUP_TOKEN'] ?? '') !== '';

if ($adminCount > 0) {
    header('Content-Type: text/html; charset=utf-8');
    echo '<!DOCTYPE html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><title>تم الإعداد</title>';
    echo '<style>body{font-family:Segoe UI,Tahoma,Arial,sans-serif;padding:28px;max-width:560px;line-height:1.6}</style></head><body>';
    echo '<h2>يوجد حساب مالك مسبقاً</h2>';
    echo '<p>لا حاجة لهذه الصفحة. <strong>احذف ملف <code>setup_once.php</code> من الخادم</strong> لأسباب أمنية.</p>';
    echo '</body></html>';
    exit;
}

$errors = [];
$success = false;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $inTok = (string) ($_POST['setup_token'] ?? '');
    $email = strtolower(trim((string) ($_POST['email'] ?? '')));
    $p1 = (string) ($_POST['password'] ?? '');
    $p2 = (string) ($_POST['password2'] ?? '');

    if (!$setupTokenConfigured) {
        $errors[] = 'لم يُضبط SETUP_TOKEN في ملف .env أو env على الخادم.';
    } elseif (!hash_equals($config['SETUP_TOKEN'], $inTok)) {
        $errors[] = 'رمز الإعداد غير صحيح.';
    }
    if (strpos($email, '@') === false) {
        $errors[] = 'أدخل بريداً صالحاً.';
    }
    if (strlen($p1) < 8) {
        $errors[] = 'كلمة المرور يجب أن لا تقل عن 8 أحرف.';
    }
    if ($p1 !== $p2) {
        $errors[] = 'تأكيد كلمة المرور غير متطابق.';
    }

    if ($errors === []) {
        try {
            $inserted = activation_admin_insert($pdo, $email, $p1, 'approver');
            if (!$inserted) {
                $errors[] = 'البريد مسجّل مسبقاً.';
            } else {
                $success = true;
            }
        } catch (InvalidArgumentException $e) {
            $errors[] = 'بيانات غير صالحة.';
        } catch (Throwable $e) {
            $errors[] = 'فشل الحفظ: ' . $e->getMessage();
        }
    }
}

header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta name="robots" content="noindex,nofollow" />
  <title>إنشاء حساب المالك — لمرة واحدة</title>
  <style>
    body { font-family: "Segoe UI", Tahoma, Arial, sans-serif; background:#f1f5f9; margin:0; padding:24px; color:#0f172a; }
    .card { max-width:440px; margin:0 auto; background:#fff; padding:24px; border-radius:12px; box-shadow:0 8px 24px rgba(15,23,42,.08); }
    h1 { font-size:1.15rem; margin:0 0 12px; }
    .muted { color:#64748b; font-size:.9rem; margin:0 0 18px; line-height:1.55; }
    label { display:block; font-weight:600; margin-top:14px; margin-bottom:6px; font-size:.9rem; }
    input { width:100%; box-sizing:border-box; padding:10px 12px; border:1px solid #cbd5e1; border-radius:8px; font-size:1rem; }
    button { margin-top:20px; width:100%; padding:12px; border:none; border-radius:8px; background:#2563eb; color:#fff; font-weight:700; cursor:pointer; font-size:1rem; }
    .err { background:#fef2f2; color:#991b1b; padding:12px; border-radius:8px; margin-bottom:14px; font-size:.9rem; }
    .ok { background:#ecfdf5; color:#065f46; padding:12px; border-radius:8px; margin-bottom:14px; font-size:.9rem; }
    code { background:#f1f5f9; padding:2px 6px; border-radius:4px; font-size:.85em; }
  </style>
</head>
<body>
  <div class="card">
    <?php if ($success): ?>
      <h1>تم إنشاء حساب المالك</h1>
      <p class="ok">يمكنك الآن تسجيل الدخول من الصفحة الرئيسية بالبريد وكلمة المرور التي اخترتها.</p>
      <p class="muted"><strong>مهم للأمان:</strong> احذف ملف <code>setup_once.php</code> من الخادم (FTP أو مدير الملفات)، وأزل أو امسح قيمة <code>SETUP_TOKEN</code> من ملف <code>.env</code>.</p>
    <?php else: ?>
      <h1>إعداد حساب المالك (مرة واحدة)</h1>
      <p class="muted">
        أضف في ملف الإعدادات (<code>.env</code> أو إن تعذّر الاسم على FTP استخدم الملف باسم <code>env</code>) السطر:
        <code>SETUP_TOKEN=...</code>
        ثم أدخل نفس الرمز في الحقل أدناه.
      </p>
      <?php if ($errors !== []): ?>
        <div class="err"><?php foreach ($errors as $er): ?><div><?= $h($er) ?></div><?php endforeach; ?></div>
      <?php endif; ?>
      <?php if (!$setupTokenConfigured): ?>
        <div class="err">لم يُضبط <code>SETUP_TOKEN</code> في <code>.env</code> أو <code>env</code> — عدّل الملف عبر FTP ثم حدّث هذه الصفحة.</div>
      <?php endif; ?>
      <form method="post" action="">
        <label for="setup_token">رمز الإعداد (من .env)</label>
        <input id="setup_token" name="setup_token" type="password" autocomplete="off" required />

        <label for="email">البريد الإلكتروني</label>
        <input id="email" name="email" type="email" autocomplete="username" required />

        <label for="password">كلمة المرور (8 أحرف على الأقل)</label>
        <input id="password" name="password" type="password" autocomplete="new-password" required />

        <label for="password2">تأكيد كلمة المرور</label>
        <input id="password2" name="password2" type="password" autocomplete="new-password" required />

        <button type="submit">إنشاء حساب المالك</button>
      </form>
    <?php endif; ?>
  </div>
</body>
</html>
