<?php
declare(strict_types=1);

/** اختبار كتالوج الميدان — php drhsn/scripts/smoke_field_catalog.php */
require __DIR__ . '/../includes/config.php';
require __DIR__ . '/../includes/db.php';
require __DIR__ . '/../includes/handlers.php';

$config = activation_config();
$pdo = activation_open_db($config['DATABASE_PATH']);
field_catalog_ensure_schema($pdo);

$org = 'smoke-catalog-org';
$email = 'fieldcatalog-smoke@example.com';
$now = activation_now_iso();
$pdo->prepare('DELETE FROM signup_requests WHERE lower(trim(email)) = ?')->execute([$email]);
$pdo->prepare(
    'INSERT INTO signup_requests (
        id, organization_id, full_name, email, phone, dial_code, password_hash, requested_at, status, email_verified
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1)',
)->execute([
    activation_uuid(),
    $org,
    'Catalog Smoke',
    $email,
    '599000001',
    '+970',
    password_hash('test1234', PASSWORD_BCRYPT),
    $now,
    'approved',
]);

$productId = activation_uuid();
$pdo->prepare('DELETE FROM field_catalog_products WHERE trim(organization_id) = trim(?)')->execute([$org]);
$pdo->prepare('DELETE FROM field_catalog_meta WHERE trim(organization_id) = trim(?)')->execute([$org]);
$pdo->prepare(
    'INSERT INTO field_catalog_meta (organization_id, version, product_count, customer_count, published_by_email, updated_at)
     VALUES (?, ?, 1, 1, ?, ?)',
)->execute([$org, $now, $email, $now]);
$pdo->prepare(
    'INSERT INTO field_catalog_products (
        id, organization_id, product_id, product_name, barcode, sale_price, unit_name, sort_order
    ) VALUES (?, ?, ?, ?, ?, ?, ?, 0)',
)->execute([
    activation_uuid(),
    $org,
    $productId,
    'حليب',
    '123456',
    5.5,
    'علبة',
]);
$customerId = activation_uuid();
$pdo->prepare(
    'INSERT INTO field_catalog_customers (
        id, organization_id, customer_id, customer_name, phone, address, customer_number, sort_order
    ) VALUES (?, ?, ?, ?, ?, ?, ?, 0)',
)->execute([
    activation_uuid(),
    $org,
    $customerId,
    'عميل تجريبي',
    '0599000000',
    'رام الله',
    'C-001',
]);

$meta = field_catalog_fetch_meta($pdo, $org);
if ($meta === null) {
    fwrite(STDERR, "meta missing\n");
    exit(1);
}
$items = field_catalog_fetch_products($pdo, $org);
$customers = field_catalog_fetch_customers($pdo, $org);
if (count($items) !== 1 || ($items[0]['productId'] ?? '') !== $productId) {
    fwrite(STDERR, "products fetch failed\n");
    exit(1);
}
if (count($customers) !== 1 || ($customers[0]['customerId'] ?? '') !== $customerId) {
    fwrite(STDERR, "customers fetch failed\n");
    exit(1);
}

echo "ok field_catalog schema + products + customers\n";

$pdo->prepare('DELETE FROM field_catalog_products WHERE trim(organization_id) = trim(?)')->execute([$org]);
$pdo->prepare('DELETE FROM field_catalog_customers WHERE trim(organization_id) = trim(?)')->execute([$org]);
$pdo->prepare('DELETE FROM field_catalog_meta WHERE trim(organization_id) = trim(?)')->execute([$org]);
$pdo->prepare('DELETE FROM signup_requests WHERE lower(trim(email)) = ?')->execute([$email]);

exit(0);
