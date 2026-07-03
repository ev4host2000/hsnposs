<?php
declare(strict_types=1);

/**
 * إنشاء حساب مالك للوحة الموافقة (جدول admins).
 *
 *   php scripts/create_admin.php owner@mizapos.com "StrongPass123"
 *   php scripts/create_admin.php auditor@mizapos.com "StrongPass123" viewer
 *   php scripts/create_admin.php billing@mizapos.com "StrongPass123" billing
 *   php scripts/create_admin.php support@mizapos.com "StrongPass123" support
 */

$root = dirname(__DIR__);
require $root . '/includes/config.php';
require $root . '/includes/db.php';

$email = strtolower(trim((string) ($argv[1] ?? '')));
$plain = (string) ($argv[2] ?? '');
$role = strtolower(trim((string) ($argv[3] ?? 'admin')));
if (!in_array($role, ['admin', 'billing', 'support', 'viewer'], true)) {
    $role = 'admin';
}

if (strpos($email, '@') === false || strlen($plain) < 8) {
    fwrite(STDERR, "Usage: php scripts/create_admin.php hsnpal99@gmail.com \"1234\" [admin|billing|support|viewer]\n");
    exit(1);
}

$config = activation_config();
$pdo = activation_open_db($config['DATABASE_PATH']);

try {
    $ok = activation_admin_insert($pdo, $email, $plain, $role);
} catch (InvalidArgumentException $e) {
    fwrite(STDERR, "Usage: php scripts/create_admin.php hsnpal99@gmail.com \"1234\" [admin|billing|support|viewer]\n");
    exit(1);
}

if (!$ok) {
    fwrite(STDERR, "البريد مسجّل مسبقاً: {$email}\n");
    exit(1);
}

echo "تم إنشاء حساب الأدمن: {$email} | role: {$role}\n";
