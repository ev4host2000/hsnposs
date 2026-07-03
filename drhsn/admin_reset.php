<?php
declare(strict_types=1);

/**
 * إعادة تعيين كلمة مرور مسؤول أو إنشاء حساب جديد — للاستخدام من المتصفح.
 *
 * 1) تأكّد أن .env (أو env) يحتوي:  SETUP_TOKEN=بعض-القيمة-السرية
 * 2) افتح: https://mizapos.com/drhsn/admin_reset.php
 * 3) أدخل الرمز نفسه + البريد + كلمة المرور الجديدة → احفظ.
 * 4) بعد الانتهاء: احذف هذا الملف من الخادم وأفرغ SETUP_TOKEN.
 *
 * يعمل حتى عند وجود حسابات admin مسبقاً (يحدّث الموجود أو ينشئ جديداً).
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
    echo '<!DOCTYPE html><html lang="ar" dir="rtl"><meta charset="utf-8"><title>خطأ</title>';
    echo '<body style="font-family:Segoe UI,Tahoma,sans-serif;padding:24px">';
    echo '<p>فشل فتح قاعدة البيانات: ' . $h($e->getMessage()) . '</p></body></html>';
    exit;
}

$setupTokenConfigured = ($config['SETUP_TOKEN'] ?? '') !== '';
$errors = [];
$success = '';

// قائمة الحسابات الموجودة (لعرضها للمسؤول كي يختار البريد الصحيح)
$existingAdmins = [];
try {
    $existingAdmins = $pdo->query(
        'SELECT email, admin_role, created_at, disabled_at FROM admins ORDER BY created_at DESC'
    )->fetchAll(PDO::FETCH_ASSOC) ?: [];
} catch (Throwable $e) {
    /* تجاهل: قد لا يوجد الجدول بعد */
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $inTok = (string) ($_POST['setup_token'] ?? '');
    $email = strtolower(trim((string) ($_POST['email'] ?? '')));
    $p1 = (string) ($_POST['password'] ?? '');
    $p2 = (string) ($_POST['password2'] ?? '');
    $role = strtolower(trim((string) ($_POST['role'] ?? 'admin')));
    if (!in_array($role, ['admin', 'billing', 'support', 'viewer'], true)) {
        $role = 'admin';
    }

    if (!$setupTokenConfigured) {
        $errors[] = 'لم يُضبط SETUP_TOKEN في ملف .env على الخادم.';
    } elseif (!hash_equals($config['SETUP_TOKEN'], $inTok)) {
        $errors[] = 'رمز الإعداد غير صحيح.';
    }
    if (strpos($email, '@') === false) {
        $errors[] = 'أدخل بريداً صحيحاً يحتوي على @.';
    }
    if (strlen($p1) < 8) {
        $errors[] = 'كلمة المرور لا تقل عن 8 أحرف.';
    }
    if ($p1 !== $p2) {
        $errors[] = 'تأكيد كلمة المرور غير متطابق.';
    }

    if ($errors === []) {
        try {
            $st = $pdo->prepare('SELECT id, email, admin_role FROM admins WHERE lower(trim(email)) = ?');
            $st->execute([$email]);
            $existing = $st->fetch(PDO::FETCH_ASSOC);

            $hash = password_hash($p1, PASSWORD_BCRYPT, ['cost' => 10]);
            $acl = $role === 'viewer' ? 'viewer' : 'approver';

            if ($existing) {
                $up = $pdo->prepare(
                    'UPDATE admins SET password_hash = ?, admin_role = ?, acl = ?, disabled_at = NULL
                     WHERE id = ?'
                );
                $up->execute([$hash, $role, $acl, (string) $existing['id']]);
                $success = 'تم تحديث كلمة مرور الحساب «' . $email . '» وتفعيله بصلاحية «' . $role . '».';
            } else {
                $now = (new DateTimeImmutable('now', new DateTimeZone('UTC')))
                    ->format('Y-m-d\TH:i:s.v\Z');
                $ins = $pdo->prepare(
                    'INSERT INTO admins (id, email, password_hash, created_at, acl, admin_role)
                     VALUES (?, ?, ?, ?, ?, ?)'
                );
                $ins->execute([activation_uuid(), $email, $hash, $now, $acl, $role]);
                $success = 'تم إنشاء حساب جديد «' . $email . '» بصلاحية «' . $role . '».';
            }

            // أعد قائمة الحسابات بعد التعديل
            $existingAdmins = $pdo->query(
                'SELECT email, admin_role, created_at, disabled_at FROM admins ORDER BY created_at DESC'
            )->fetchAll(PDO::FETCH_ASSOC) ?: [];
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
  <title>إعادة تعيين كلمة مرور المسؤول</title>
  <style>
    body { font-family: 'Segoe UI', Tahoma, Arial, sans-serif; background: #f1f5f9; margin: 0; padding: 24px; color: #0f172a; }
    .card { max-width: 560px; margin: 0 auto 18px; background: #fff; padding: 26px; border-radius: 14px; box-shadow: 0 8px 24px rgba(15, 23, 42, .08); }
    h1 { font-size: 1.2rem; margin: 0 0 14px; }
    h2 { font-size: 1rem; margin: 18px 0 8px; }
    .muted { color: #64748b; font-size: .9rem; line-height: 1.65; }
    label { display: block; font-weight: 600; margin: 14px 0 6px; font-size: .92rem; }
    input, select { width: 100%; box-sizing: border-box; padding: 10px 12px; border: 1px solid #cbd5e1; border-radius: 8px; font-size: 1rem; font-family: inherit; }
    input:focus, select:focus { outline: none; border-color: #6366f1; box-shadow: 0 0 0 3px rgba(99, 102, 241, .15); }
    button { margin-top: 22px; width: 100%; padding: 12px; border: none; border-radius: 8px; background: linear-gradient(135deg, #6366f1, #8b5cf6); color: #fff; font-weight: 700; cursor: pointer; font-size: 1rem; }
    button:hover { opacity: .95; }
    .err { background: #fef2f2; color: #991b1b; padding: 12px 14px; border-radius: 8px; margin-bottom: 14px; font-size: .92rem; }
    .ok { background: #ecfdf5; color: #065f46; padding: 12px 14px; border-radius: 8px; margin-bottom: 14px; font-size: .92rem; font-weight: 600; }
    code { background: #f1f5f9; padding: 2px 6px; border-radius: 4px; font-size: .85em; }
    table { width: 100%; border-collapse: collapse; font-size: .9rem; margin-top: 8px; }
    th, td { text-align: right; padding: 8px 10px; border-bottom: 1px solid #e2e8f0; }
    th { background: #f8fafc; font-weight: 700; color: #475569; }
    .pill { display: inline-block; padding: 2px 8px; border-radius: 999px; font-size: .78em; font-weight: 700; }
    .pill-on { background: #dcfce7; color: #166534; }
    .pill-off { background: #fee2e2; color: #991b1b; }
    .warning { background: #fef3c7; color: #92400e; padding: 12px 14px; border-radius: 8px; margin-bottom: 12px; font-size: .88rem; }
  </style>
</head>
<body>
  <div class="card">
    <h1>إعادة تعيين كلمة مرور مسؤول</h1>
    <p class="muted">
      تستخدم هذه الصفحة لإعادة تعيين كلمة سر حساب موجود، أو إنشاء حساب admin جديد عند نسيان البيانات.
      أضف في <code>.env</code> سطر <code>SETUP_TOKEN=...</code> ثم أدخل نفس الرمز هنا.
    </p>

    <?php if (!$setupTokenConfigured): ?>
      <div class="err">لم يُضبط <code>SETUP_TOKEN</code> في <code>.env</code>. أضفه عبر FTP/cPanel ثم حدّث هذه الصفحة.</div>
    <?php endif; ?>

    <?php if ($success !== ''): ?>
      <div class="ok"><?= $h($success) ?></div>
      <div class="warning">
        <strong>هام للأمان:</strong> بعد التحقق من نجاح الدخول، احذف ملف
        <code>admin_reset.php</code> من الخادم وأفرغ <code>SETUP_TOKEN</code> من <code>.env</code>.
      </div>
    <?php endif; ?>

    <?php if ($errors !== []): ?>
      <div class="err">
        <?php foreach ($errors as $er): ?>
          <div><?= $h($er) ?></div>
        <?php endforeach; ?>
      </div>
    <?php endif; ?>

    <form method="post" action="">
      <label for="setup_token">رمز الإعداد (من <code>.env</code>)</label>
      <input id="setup_token" name="setup_token" type="password" autocomplete="off" required />

      <label for="email">البريد الإلكتروني للمسؤول</label>
      <input id="email" name="email" type="email" autocomplete="username" placeholder="admin@example.com"
             value="<?= $h((string) ($_POST['email'] ?? '')) ?>" required />

      <label for="role">الصلاحية</label>
      <select id="role" name="role">
        <option value="admin">admin (مالك كامل)</option>
        <option value="billing">billing (تمديد/تجميد)</option>
        <option value="support">support (موافقة/تجميد)</option>
        <option value="viewer">viewer (قراءة فقط)</option>
      </select>

      <label for="password">كلمة المرور الجديدة (8 أحرف على الأقل)</label>
      <input id="password" name="password" type="password" autocomplete="new-password" required />

      <label for="password2">تأكيد كلمة المرور</label>
      <input id="password2" name="password2" type="password" autocomplete="new-password" required />

      <button type="submit">حفظ كلمة المرور</button>
    </form>
  </div>

  <?php if ($existingAdmins !== []): ?>
    <div class="card">
      <h2>الحسابات الموجودة في قاعدة البيانات</h2>
      <p class="muted">استخدم نفس البريد المسجَّل هنا أعلاه إن أردت إعادة تعيين كلمة سر حساب موجود.</p>
      <table>
        <thead>
          <tr><th>البريد</th><th>الصلاحية</th><th>الحالة</th><th>تاريخ الإنشاء</th></tr>
        </thead>
        <tbody>
        <?php foreach ($existingAdmins as $a): ?>
          <tr>
            <td><code><?= $h((string) $a['email']) ?></code></td>
            <td><?= $h((string) ($a['admin_role'] ?? '')) ?></td>
            <td>
              <?php if (!empty($a['disabled_at'])): ?>
                <span class="pill pill-off">معطّل</span>
              <?php else: ?>
                <span class="pill pill-on">مفعّل</span>
              <?php endif; ?>
            </td>
            <td style="color:#64748b;font-size:.85em"><?= $h((string) ($a['created_at'] ?? '')) ?></td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  <?php else: ?>
    <div class="card">
      <h2>لا توجد حسابات admin بعد</h2>
      <p class="muted">سيُنشأ أول حساب عند الحفظ بالأعلى. هو سيكون «المالك» (دور admin) القادر على إدارة بقية الحسابات.</p>
    </div>
  <?php endif; ?>
</body>
</html>
