<?php
declare(strict_types=1);

/** اختبار سريع لـ API طلبات الميدان — يُشغَّل محلياً: php scripts/smoke_field_orders.php */
require __DIR__ . '/../includes/config.php';
require __DIR__ . '/../includes/db.php';
require __DIR__ . '/../includes/jwt.php';
require __DIR__ . '/../includes/handlers.php';

$config = activation_config();
$pdo = activation_open_db($config['DATABASE_PATH']);
field_orders_ensure_schema($pdo);

$org = 'smoke-test-org';
$email = 'fieldorders-smoke@example.com';
$now = activation_now_iso();
$pdo->prepare('DELETE FROM signup_requests WHERE lower(trim(email)) = ?')->execute([$email]);
$pdo->prepare(
    'INSERT INTO signup_requests (
        id, organization_id, full_name, email, phone, dial_code, password_hash, requested_at, status, email_verified
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1)',
)->execute([
    activation_uuid(),
    $org,
    'Smoke Tester',
    $email,
    '599000000',
    '+970',
    password_hash('test1234', PASSWORD_BCRYPT),
    $now,
    'approved',
]);

$orderId = null;
try {
    $pdo->beginTransaction();
    $orderId = activation_uuid();
    $pdo->prepare(
        'INSERT INTO field_orders (
            id, organization_id, client_order_id, status,
            submitter_email, submitter_name, customer_name, created_at, updated_at
        ) VALUES (?, ?, ?, \'pending\', ?, ?, ?, ?, ?)',
    )->execute([$orderId, $org, 'client-smoke-1', $email, 'Smoke', 'عميل تجريبي', $now, $now]);
    $pdo->prepare(
        'INSERT INTO field_order_lines (
            id, field_order_id, line_index, product_name, quantity
        ) VALUES (?, ?, 0, ?, ?)',
    )->execute([activation_uuid(), $orderId, 'حليب', 2.0]);
    $pdo->commit();
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    fwrite(STDERR, 'seed failed: ' . $e->getMessage() . PHP_EOL);
    exit(1);
}

$listed = field_orders_fetch_public($pdo, $orderId, $org);
if ($listed === null || ($listed['status'] ?? '') !== 'pending') {
    fwrite(STDERR, "fetch failed\n");
    exit(1);
}

$pendingSt = $pdo->prepare(
    'SELECT COUNT(*) FROM field_orders WHERE trim(organization_id) = trim(?) AND status = \'pending\'',
);
$pendingSt->execute([$org]);
$pendingCount = (int) $pendingSt->fetchColumn();
if ($pendingCount < 1) {
    fwrite(STDERR, "pending list empty\n");
    exit(1);
}

$nowReview = activation_now_iso();
$pdo->prepare(
    'UPDATE field_orders SET status = \'approved\', reviewed_by_email = ?, reviewed_at = ?, updated_at = ? WHERE id = ?',
)->execute([$email, $nowReview, $nowReview, $orderId]);

$rowByClient = field_orders_fetch_row_by_reference($pdo, '', 'client-smoke-1', $org);
if ($rowByClient === null || ($rowByClient['id'] ?? '') !== $orderId) {
    fwrite(STDERR, "client order lookup failed\n");
    exit(1);
}

$approved = field_orders_fetch_public($pdo, $orderId, $org);
if ($approved === null || ($approved['status'] ?? '') !== 'approved') {
    fwrite(STDERR, "approve failed\n");
    exit(1);
}

echo "ok field_orders schema + fetch + pending + approve (order {$orderId})\n";

$pdo->prepare('DELETE FROM field_order_lines WHERE field_order_id = ?')->execute([$orderId]);
$pdo->prepare('DELETE FROM field_orders WHERE id = ?')->execute([$orderId]);
$pdo->prepare('DELETE FROM signup_requests WHERE lower(trim(email)) = ?')->execute([$email]);

exit(0);
