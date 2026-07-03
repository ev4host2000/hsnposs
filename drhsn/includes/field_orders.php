<?php
declare(strict_types=1);

require_once __DIR__ . '/distributor_license.php';

/**
 * طلبات الميدان (field orders) — MVP المرحلة 1.
 * مسارات جديدة فقط؛ لا تغيّر تفعيل/قسائم/ترخيص المشتركين الحاليين.
 */

/** @return list<string> */
function field_orders_valid_statuses(): array
{
    return ['pending', 'approved', 'rejected'];
}

function field_orders_ensure_schema(PDO $pdo): void
{
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS field_orders (
            id TEXT PRIMARY KEY,
            organization_id TEXT NOT NULL,
            client_order_id TEXT,
            status TEXT NOT NULL DEFAULT 'pending',
            submitter_email TEXT NOT NULL,
            submitter_name TEXT,
            distributor_user_id TEXT,
            distributor_display_name TEXT,
            installation_id TEXT,
            customer_id TEXT,
            customer_name TEXT NOT NULL,
            customer_phone TEXT,
            customer_address TEXT,
            notes TEXT,
            reject_reason TEXT,
            reviewed_by_email TEXT,
            reviewed_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE UNIQUE INDEX IF NOT EXISTS uq_field_orders_client
            ON field_orders(organization_id, client_order_id)
            WHERE client_order_id IS NOT NULL AND trim(client_order_id) <> '';
        CREATE INDEX IF NOT EXISTS idx_field_orders_org_status_created
            ON field_orders(organization_id, status, created_at DESC);
        CREATE TABLE IF NOT EXISTS field_order_lines (
            id TEXT PRIMARY KEY,
            field_order_id TEXT NOT NULL,
            line_index INTEGER NOT NULL,
            product_id TEXT,
            product_name TEXT NOT NULL,
            barcode TEXT,
            quantity REAL NOT NULL,
            unit_price REAL,
            unit_name TEXT,
            FOREIGN KEY (field_order_id) REFERENCES field_orders(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_field_order_lines_order
            ON field_order_lines(field_order_id, line_index);
    ");
    field_orders_ensure_payment_columns($pdo);
    field_orders_ensure_inventory_source_column($pdo);
}

function field_orders_ensure_inventory_source_column(PDO $pdo): void
{
    try {
        $pdo->exec(
            "ALTER TABLE field_orders ADD COLUMN inventory_source TEXT NOT NULL DEFAULT 'main'",
        );
    } catch (Throwable $e) {
        /* العمود موجود */
    }
}

function field_orders_ensure_payment_columns(PDO $pdo): void
{
    $columns = [
        'payment_type' => 'TEXT',
        'paid_amount' => 'REAL',
        'discount_amount' => 'REAL NOT NULL DEFAULT 0',
        'tax_percent' => 'REAL NOT NULL DEFAULT 0',
        'grand_total' => 'REAL',
        'payment_splits_json' => 'TEXT',
    ];
    foreach ($columns as $name => $ddl) {
        try {
            $pdo->exec("ALTER TABLE field_orders ADD COLUMN {$name} {$ddl}");
        } catch (Throwable $e) {
            /* العمود موجود */
        }
    }
}

/** @param array<string,mixed> $body */
function field_orders_parse_payment(array $body): array
{
    $paymentType = strtolower(trim((string) ($body['paymentType'] ?? $body['payment_type'] ?? 'deferred')));
    if ($paymentType === '') {
        $paymentType = 'deferred';
    }
    $paid = (float) ($body['paidAmount'] ?? $body['paid_amount'] ?? 0);
    if (!is_finite($paid) || $paid < 0) {
        $paid = 0.0;
    }
    $discount = (float) ($body['discountAmount'] ?? $body['discount_amount'] ?? 0);
    if (!is_finite($discount) || $discount < 0) {
        $discount = 0.0;
    }
    $tax = (float) ($body['taxPercent'] ?? $body['tax_percent'] ?? 0);
    if (!is_finite($tax) || $tax < 0) {
        $tax = 0.0;
    }
    $grand = $body['grandTotal'] ?? $body['grand_total'] ?? null;
    $grandTotal = null;
    if ($grand !== null && $grand !== '') {
        $grandTotal = (float) $grand;
        if (!is_finite($grandTotal) || $grandTotal < 0) {
            $grandTotal = null;
        }
    }
    $splitsRaw = $body['paymentSplits'] ?? $body['payment_splits'] ?? null;
    $splitsJson = null;
    if (is_array($splitsRaw) && $splitsRaw !== []) {
        $encoded = json_encode($splitsRaw, JSON_UNESCAPED_UNICODE);
        if (is_string($encoded) && $encoded !== '[]') {
            $splitsJson = $encoded;
        }
    }

    return [
        'payment_type' => $paymentType,
        'paid_amount' => $paid,
        'discount_amount' => $discount,
        'tax_percent' => $tax,
        'grand_total' => $grandTotal,
        'payment_splits_json' => $splitsJson,
    ];
}

function field_orders_normalize_inventory_source(string $raw): string
{
    $v = strtolower(trim($raw));
    if ($v === 'truck') {
        return 'truck';
    }

    return 'main';
}

/** @param array<string,mixed> $body */
function field_orders_parse_inventory_source(array $body): string
{
    $raw = $body['inventorySource'] ?? $body['inventory_source'] ?? 'main';

    return field_orders_normalize_inventory_source((string) $raw);
}

function field_orders_shared_secret_ok(array $config): bool
{
    $sec = (string) $config['REMOTE_SIGNUP_SHARED_SECRET'];
    if ($sec === '') {
        return true;
    }
    $h = (string) ($_SERVER['HTTP_X_INSTALLATION_SECRET'] ?? '');

    return hash_equals($sec, $h);
}

/** @return array{organization_id:string,email:string,full_name:string}|null */
function field_orders_lookup_license_row(PDO $pdo, string $organizationId, string $email): ?array
{
    $organizationId = trim($organizationId);
    $email = strtolower(trim($email));
    if (strpos($email, '@') === false) {
        return null;
    }

    if ($organizationId !== '') {
        $st = $pdo->prepare(
            'SELECT organization_id, email_normalized AS email
             FROM license_snapshots
             WHERE trim(organization_id) = trim(?) AND email_normalized = ?
             LIMIT 1',
        );
        $st->execute([$organizationId, $email]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if ($row) {
            return [
                'organization_id' => trim((string) $row['organization_id']),
                'email' => strtolower(trim((string) $row['email'])),
                'full_name' => '',
            ];
        }
    }

    $st2 = $pdo->prepare(
        'SELECT organization_id, email_normalized AS email
         FROM license_snapshots
         WHERE email_normalized = ?
         ORDER BY updated_at DESC
         LIMIT 1',
    );
    $st2->execute([$email]);
    $row = $st2->fetch(PDO::FETCH_ASSOC);
    if ($row) {
        return [
            'organization_id' => trim((string) $row['organization_id']),
            'email' => strtolower(trim((string) $row['email'])),
            'full_name' => '',
        ];
    }

    $st3 = $pdo->prepare(
        "SELECT redeemed_by_organization_id AS organization_id,
                redeemed_by_email AS email
         FROM vouchers
         WHERE lower(trim(redeemed_by_email)) = ?
           AND trim(redeemed_by_organization_id) <> ''
           AND status IN ('redeemed', 'active')
         ORDER BY COALESCE(first_redeemed_at, '') DESC
         LIMIT 1",
    );
    $st3->execute([$email]);
    $row = $st3->fetch(PDO::FETCH_ASSOC);
    if ($row) {
        return [
            'organization_id' => trim((string) $row['organization_id']),
            'email' => strtolower(trim((string) $row['email'])),
            'full_name' => '',
        ];
    }

    return null;
}

/** @return array{organization_id:string,email:string,full_name:string}|null */
function field_orders_lookup_signup_row(PDO $pdo, string $organizationId, string $email): ?array
{
    $organizationId = trim($organizationId);
    $email = strtolower(trim($email));
    if ($organizationId === '' || strpos($email, '@') === false) {
        return null;
    }
    $st = $pdo->prepare(
        "SELECT organization_id, email, full_name FROM signup_requests
         WHERE trim(organization_id) = trim(?) AND lower(trim(email)) = ?
         ORDER BY requested_at DESC LIMIT 1",
    );
    $st->execute([$organizationId, $email]);
    $row = $st->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        $st2 = $pdo->prepare(
            "SELECT organization_id, email, full_name FROM signup_requests
             WHERE lower(trim(email)) = ?
             ORDER BY requested_at DESC LIMIT 1",
        );
        $st2->execute([$email]);
        $row = $st2->fetch(PDO::FETCH_ASSOC);
    }
    if (!$row) {
        return field_orders_lookup_license_row($pdo, $organizationId, $email);
    }

    return [
        'organization_id' => trim((string) $row['organization_id']),
        'email' => strtolower(trim((string) $row['email'])),
        'full_name' => (string) ($row['full_name'] ?? ''),
    ];
}

/**
 * سياق مؤسسة للطلب: سر التثبيت + organizationId + email (أولاً) أو JWT مشترك.
 *
 * @return array{
 *   organization_id:string,
 *   email:string,
 *   full_name:string,
 *   auth:string
 * }
 */
function field_orders_require_org_context(PDO $pdo, array $config, array $bodyOrQuery): array
{
    $organizationId = trim((string) ($bodyOrQuery['organizationId'] ?? ''));
    $email = strtolower(trim((string) ($bodyOrQuery['email'] ?? '')));

    // يطابق الجوال: org+email مع سر التثبيت قبل JWT حتى لا يختلف سياق الاعتماد عن القائمة.
    if (field_orders_shared_secret_ok($config)) {
        $row = field_orders_lookup_signup_row($pdo, $organizationId, $email);
        if ($row !== null) {
            return [
                'organization_id' => $row['organization_id'],
                'email' => $row['email'],
                'full_name' => $row['full_name'],
                'auth' => 'installation_secret',
            ];
        }
    }

    $token = activation_bearer_token();
    if ($token !== null && $token !== '') {
        $sub = activation_require_subscriber($config, $pdo);

        return [
            'organization_id' => $sub['organization_id'],
            'email' => $sub['email'],
            'full_name' => $sub['full_name'],
            'auth' => 'subscriber_jwt',
        ];
    }

    activation_require_shared_secret($config);
    if ($organizationId === '' || strpos($email, '@') === false) {
        activation_json(400, ['error' => 'validation']);
    }
    $row = field_orders_lookup_signup_row($pdo, $organizationId, $email);
    if ($row === null) {
        activation_json(403, ['error' => 'forbidden']);
    }

    return [
        'organization_id' => $row['organization_id'],
        'email' => $row['email'],
        'full_name' => $row['full_name'],
        'auth' => 'installation_secret',
    ];
}

/**
 * سياق منشأة لـ API الميدان — اشتراك سحابة كامل أو تجربة محدودة للمشترك العادي.
 *
 * @return array{
 *   organization_id:string,
 *   email:string,
 *   full_name:string,
 *   auth:string,
 *   distributor_cloud_active:bool,
 *   distributor_trial:bool
 * }
 */
function field_orders_require_distributor_cloud_context(
    PDO $pdo,
    array $config,
    array $bodyOrQuery,
): array {
    $ctx = field_orders_require_org_context($pdo, $config, $bodyOrQuery);
    $cloudActive = distributor_license_is_active_for_org($pdo, $ctx['organization_id']);
    $ctx['distributor_cloud_active'] = $cloudActive;
    $ctx['distributor_trial'] = !$cloudActive;

    return $ctx;
}

/** @return array<string,mixed>|null */
function field_orders_fetch_row_by_reference(
    PDO $pdo,
    string $orderId,
    string $clientOrderId,
    string $organizationId,
): ?array {
    $orderId = trim($orderId);
    if ($orderId !== '') {
        $st = $pdo->prepare('SELECT * FROM field_orders WHERE id = ? LIMIT 1');
        $st->execute([$orderId]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if ($row) {
            return $row;
        }
    }
    $clientOrderId = trim($clientOrderId);
    $organizationId = trim($organizationId);
    if ($clientOrderId !== '' && $organizationId !== '') {
        $st = $pdo->prepare(
            'SELECT * FROM field_orders
             WHERE trim(organization_id) = trim(?) AND client_order_id = ?
             LIMIT 1',
        );
        $st->execute([$organizationId, $clientOrderId]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if ($row) {
            return $row;
        }
    }
    if ($clientOrderId !== '') {
        $st = $pdo->prepare(
            'SELECT * FROM field_orders WHERE client_order_id = ? LIMIT 1',
        );
        $st->execute([$clientOrderId]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if ($row) {
            return $row;
        }
    }

    return null;
}

function field_orders_can_access_order(PDO $pdo, array $ctx, array $row): bool
{
    $orderOrg = trim((string) $row['organization_id']);
    $ctxOrg = trim((string) $ctx['organization_id']);
    if ($orderOrg === $ctxOrg) {
        return true;
    }
    $ctxEmail = strtolower(trim((string) $ctx['email']));
    $submitter = strtolower(trim((string) ($row['submitter_email'] ?? '')));
    if ($submitter !== '' && $submitter === $ctxEmail) {
        return true;
    }
    $stAccess = $pdo->prepare(
        "SELECT 1 FROM signup_requests
         WHERE trim(organization_id) = trim(?) AND lower(trim(email)) = ?
         LIMIT 1",
    );
    $stAccess->execute([$orderOrg, $ctxEmail]);

    return (bool) $stAccess->fetch();
}

/** @return array<string,mixed>|null */
function field_orders_row_to_public(array $row, array $lines): array
{
    return [
        'id' => (string) $row['id'],
        'organizationId' => (string) $row['organization_id'],
        'clientOrderId' => (string) ($row['client_order_id'] ?? ''),
        'status' => (string) $row['status'],
        'submitterEmail' => (string) $row['submitter_email'],
        'submitterName' => (string) ($row['submitter_name'] ?? ''),
        'distributorUserId' => (string) ($row['distributor_user_id'] ?? ''),
        'distributorDisplayName' => (string) ($row['distributor_display_name'] ?? ''),
        'installationId' => (string) ($row['installation_id'] ?? ''),
        'customer' => [
            'id' => (string) ($row['customer_id'] ?? ''),
            'name' => (string) $row['customer_name'],
            'phone' => (string) ($row['customer_phone'] ?? ''),
            'address' => (string) ($row['customer_address'] ?? ''),
        ],
        'notes' => (string) ($row['notes'] ?? ''),
        'paymentType' => (string) ($row['payment_type'] ?? 'deferred'),
        'paidAmount' => isset($row['paid_amount']) ? (float) $row['paid_amount'] : 0.0,
        'discountAmount' => isset($row['discount_amount']) ? (float) $row['discount_amount'] : 0.0,
        'taxPercent' => isset($row['tax_percent']) ? (float) $row['tax_percent'] : 0.0,
        'grandTotal' => $row['grand_total'] === null ? null : (float) $row['grand_total'],
        'paymentSplits' => field_orders_decode_payment_splits(
            (string) ($row['payment_splits_json'] ?? ''),
        ),
        'inventorySource' => field_orders_normalize_inventory_source(
            (string) ($row['inventory_source'] ?? 'main'),
        ),
        'rejectReason' => (string) ($row['reject_reason'] ?? ''),
        'reviewedByEmail' => (string) ($row['reviewed_by_email'] ?? ''),
        'reviewedAt' => (string) ($row['reviewed_at'] ?? ''),
        'createdAt' => (string) $row['created_at'],
        'updatedAt' => (string) $row['updated_at'],
        'lines' => $lines,
    ];
}

/** @return array<string,mixed>|null */
function field_orders_fetch_public(PDO $pdo, string $orderId, string $organizationId): ?array
{
    $st = $pdo->prepare(
        'SELECT * FROM field_orders WHERE id = ? AND trim(organization_id) = trim(?) LIMIT 1',
    );
    $st->execute([$orderId, $organizationId]);
    $row = $st->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return null;
    }
    $lines = field_orders_fetch_lines($pdo, $orderId);

    return field_orders_row_to_public($row, $lines);
}

/** @return list<array<string,mixed>> */
function field_orders_fetch_lines(PDO $pdo, string $orderId): array
{
    $st = $pdo->prepare(
        'SELECT * FROM field_order_lines WHERE field_order_id = ? ORDER BY line_index ASC',
    );
    $st->execute([$orderId]);
    $out = [];
    foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $ln) {
        $out[] = [
            'id' => (string) $ln['id'],
            'product_id' => (string) ($ln['product_id'] ?? ''),
            'lineIndex' => (int) $ln['line_index'],
            'productId' => (string) ($ln['product_id'] ?? ''),
            'productName' => (string) $ln['product_name'],
            'barcode' => (string) ($ln['barcode'] ?? ''),
            'quantity' => (float) $ln['quantity'],
            'unitPrice' => $ln['unit_price'] !== null ? (float) $ln['unit_price'] : null,
            'unitName' => (string) ($ln['unit_name'] ?? ''),
        ];
    }

    return $out;
}

/** @return list<array<string,mixed>> */
function field_orders_decode_payment_splits(string $json): array
{
    $json = trim($json);
    if ($json === '') {
        return [];
    }
    $decoded = json_decode($json, true);
    if (!is_array($decoded)) {
        return [];
    }
    $out = [];
    foreach ($decoded as $row) {
        if (!is_array($row)) {
            continue;
        }
        $pt = strtolower(trim((string) ($row['paymentType'] ?? $row['payment_type'] ?? '')));
        $amt = (float) ($row['amount'] ?? 0);
        if ($pt === '' || !is_finite($amt) || $amt <= 0) {
            continue;
        }
        $out[] = ['paymentType' => $pt, 'amount' => $amt];
    }

    return $out;
}

/**
 * @param list<array<string,mixed>> $rawLines
 * @return list<array{
 *   product_id:?string,
 *   product_name:string,
 *   barcode:string,
 *   quantity:float,
 *   unit_price:?float,
 *   unit_name:string
 * }>
 */
function field_orders_parse_lines(array $rawLines): array
{
    if ($rawLines === []) {
        activation_json(400, ['error' => 'lines_required']);
    }
    $parsed = [];
    foreach ($rawLines as $i => $ln) {
        if (!is_array($ln)) {
            activation_json(400, ['error' => 'validation']);
        }
        $productName = trim((string) ($ln['productName'] ?? $ln['product_name'] ?? ''));
        if ($productName === '') {
            activation_json(400, ['error' => 'validation']);
        }
        $qty = (float) ($ln['quantity'] ?? 0);
        if (!is_finite($qty) || $qty <= 0) {
            activation_json(400, ['error' => 'validation']);
        }
        $unitPriceRaw = $ln['unitPrice'] ?? $ln['unit_price'] ?? null;
        $unitPrice = null;
        if ($unitPriceRaw !== null && $unitPriceRaw !== '') {
            $unitPrice = (float) $unitPriceRaw;
            if (!is_finite($unitPrice) || $unitPrice < 0) {
                activation_json(400, ['error' => 'validation']);
            }
        }
        $parsed[] = [
            'product_id' => trim((string) ($ln['productId'] ?? $ln['product_id'] ?? '')) ?: null,
            'product_name' => $productName,
            'barcode' => trim((string) ($ln['barcode'] ?? '')),
            'quantity' => $qty,
            'unit_price' => $unitPrice,
            'unit_name' => trim((string) ($ln['unitName'] ?? $ln['unit_name'] ?? '')),
        ];
    }

    return $parsed;
}

function field_orders_handle_create(PDO $pdo, array $config): void
{
    $body = activation_json_body();
    $ctx = field_orders_require_distributor_cloud_context($pdo, $config, $body);

    $organizationId = $ctx['organization_id'];
    $clientOrderId = trim((string) ($body['clientOrderId'] ?? $body['client_order_id'] ?? ''));
    if ($clientOrderId !== '') {
        $dup = $pdo->prepare(
            'SELECT id FROM field_orders
             WHERE trim(organization_id) = trim(?) AND client_order_id = ? LIMIT 1',
        );
        $dup->execute([$organizationId, $clientOrderId]);
        $existingId = (string) ($dup->fetchColumn() ?: '');
        if ($existingId !== '') {
            $order = field_orders_fetch_public($pdo, $existingId, $organizationId);
            activation_json(200, ['ok' => true, 'duplicate' => true, 'order' => $order]);
        }
    }

    $customer = is_array($body['customer'] ?? null) ? $body['customer'] : [];
    $customerName = trim((string) ($customer['name'] ?? $body['customerName'] ?? ''));
    if ($customerName === '') {
        activation_json(400, ['error' => 'customer_required']);
    }

    $lines = field_orders_parse_lines(
        is_array($body['lines'] ?? null) ? $body['lines'] : [],
    );
    $payment = field_orders_parse_payment($body);
    $inventorySource = field_orders_parse_inventory_source($body);

    $now = activation_now_iso();
    $orderId = activation_uuid();
    $distributorUserId = trim((string) ($body['distributorUserId'] ?? $body['distributor_user_id'] ?? ''));
    $distributorDisplayName = trim((string) (
        $body['distributorDisplayName'] ?? $body['distributor_display_name'] ?? $ctx['full_name']
    ));
    $installationId = trim((string) ($body['installationId'] ?? $body['installation_id'] ?? ''));

    try {
        $pdo->beginTransaction();
        $ins = $pdo->prepare(
            'INSERT INTO field_orders (
                id, organization_id, client_order_id, status,
                submitter_email, submitter_name,
                distributor_user_id, distributor_display_name, installation_id,
                customer_id, customer_name, customer_phone, customer_address,
                notes, payment_type, paid_amount, discount_amount, tax_percent,
                grand_total, payment_splits_json, inventory_source,
                reject_reason, reviewed_by_email, reviewed_at,
                created_at, updated_at
            ) VALUES (
                ?, ?, ?, \'pending\',
                ?, ?,
                ?, ?, ?,
                ?, ?, ?, ?,
                ?, ?, ?, ?, ?,
                ?, ?, ?,
                NULL, NULL, NULL,
                ?, ?
            )',
        );
        $ins->execute([
            $orderId,
            $organizationId,
            $clientOrderId !== '' ? $clientOrderId : null,
            $ctx['email'],
            $ctx['full_name'],
            $distributorUserId !== '' ? $distributorUserId : null,
            $distributorDisplayName !== '' ? $distributorDisplayName : null,
            $installationId !== '' ? $installationId : null,
            trim((string) ($customer['id'] ?? $body['customerId'] ?? '')) ?: null,
            $customerName,
            trim((string) ($customer['phone'] ?? '')) ?: null,
            trim((string) ($customer['address'] ?? '')) ?: null,
            trim((string) ($body['notes'] ?? '')) ?: null,
            $payment['payment_type'],
            $payment['paid_amount'],
            $payment['discount_amount'],
            $payment['tax_percent'],
            $payment['grand_total'],
            $payment['payment_splits_json'],
            $inventorySource,
            $now,
            $now,
        ]);

        $lineIns = $pdo->prepare(
            'INSERT INTO field_order_lines (
                id, field_order_id, line_index,
                product_id, product_name, barcode, quantity, unit_price, unit_name
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        );
        foreach ($lines as $idx => $ln) {
            $lineIns->execute([
                activation_uuid(),
                $orderId,
                $idx,
                $ln['product_id'],
                $ln['product_name'],
                $ln['barcode'] !== '' ? $ln['barcode'] : null,
                $ln['quantity'],
                $ln['unit_price'],
                $ln['unit_name'] !== '' ? $ln['unit_name'] : null,
            ]);
        }
        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        error_log('[field_orders] create: ' . $e->getMessage());
        activation_json(500, ['error' => 'server']);
    }

    $order = field_orders_fetch_public($pdo, $orderId, $organizationId);
    activation_json(201, ['ok' => true, 'order' => $order]);
}

function field_orders_handle_list(PDO $pdo, array $config): void
{
    $ctx = field_orders_require_distributor_cloud_context($pdo, $config, $_GET);
    $organizationId = $ctx['organization_id'];
    $installationId = trim((string) ($_GET['installationId'] ?? $_GET['installation_id'] ?? ''));
    $statusFilter = trim((string) ($_GET['status'] ?? 'all'));
    $limit = (int) ($_GET['limit'] ?? 100);
    if ($limit < 1) {
        $limit = 1;
    }
    if ($limit > 200) {
        $limit = 200;
    }

    $sql = 'SELECT * FROM field_orders WHERE trim(organization_id) = trim(?)';
    $args = [$organizationId];
    if ($installationId !== '') {
        $sql .= ' AND installation_id = ?';
        $args[] = $installationId;
    }
    if (in_array($statusFilter, field_orders_valid_statuses(), true)) {
        $sql .= ' AND status = ?';
        $args[] = $statusFilter;
    }
    $sql .= ' ORDER BY created_at DESC LIMIT ?';

    $st = $pdo->prepare($sql);
    foreach ($args as $i => $arg) {
        $st->bindValue($i + 1, $arg);
    }
    $st->bindValue(count($args) + 1, $limit, PDO::PARAM_INT);
    $st->execute();
    $rows = $st->fetchAll(PDO::FETCH_ASSOC);
    $items = [];
    foreach ($rows as $row) {
        $items[] = field_orders_row_to_public(
            $row,
            field_orders_fetch_lines($pdo, (string) $row['id']),
        );
    }

    activation_json(200, ['ok' => true, 'items' => $items, 'count' => count($items)]);
}

function field_orders_handle_list_pending(PDO $pdo, array $config): void
{
    $ctx = field_orders_require_distributor_cloud_context($pdo, $config, $_GET);
    $organizationId = $ctx['organization_id'];
    $limit = (int) ($_GET['limit'] ?? 50);
    if ($limit < 1) {
        $limit = 1;
    }
    if ($limit > 200) {
        $limit = 200;
    }

    $st = $pdo->prepare(
        'SELECT * FROM field_orders
         WHERE trim(organization_id) = trim(?) AND status = \'pending\'
         ORDER BY created_at DESC
         LIMIT ?',
    );
    $st->bindValue(1, $organizationId);
    $st->bindValue(2, $limit, PDO::PARAM_INT);
    $st->execute();
    $rows = $st->fetchAll(PDO::FETCH_ASSOC);
    $items = [];
    foreach ($rows as $row) {
        $items[] = field_orders_row_to_public(
            $row,
            field_orders_fetch_lines($pdo, (string) $row['id']),
        );
    }

    activation_json(200, ['ok' => true, 'items' => $items, 'count' => count($items)]);
}

function field_orders_handle_get_one(PDO $pdo, array $config, string $orderId): void
{
    $ctx = field_orders_require_distributor_cloud_context($pdo, $config, $_GET);
    $order = field_orders_fetch_public($pdo, $orderId, $ctx['organization_id']);
    if ($order === null) {
        activation_json(404, ['error' => 'not_found']);
    }
    activation_json(200, ['ok' => true, 'order' => $order]);
}

function field_orders_handle_review(PDO $pdo, array $config, string $orderId, string $newStatus): void
{
    $body = activation_json_body();
    if ($newStatus === 'from_body') {
        $action = strtolower(trim((string) ($body['action'] ?? '')));
        if ($action === 'approve') {
            $newStatus = 'approved';
        } elseif ($action === 'reject') {
            $newStatus = 'rejected';
        } else {
            activation_json(400, ['error' => 'validation']);
        }
        $orderId = trim((string) ($body['orderId'] ?? $body['id'] ?? ''));
    }
    if (!in_array($newStatus, ['approved', 'rejected'], true)) {
        activation_json(400, ['error' => 'validation']);
    }
    $ctx = field_orders_require_distributor_cloud_context($pdo, $config, array_merge($_GET, $body));
    $organizationId = trim($ctx['organization_id']);
    $clientOrderId = trim((string) (
        $body['clientOrderId'] ?? $body['client_order_id'] ?? $_GET['clientOrderId'] ?? ''
    ));

    $row = field_orders_fetch_row_by_reference(
        $pdo,
        $orderId,
        $clientOrderId,
        $organizationId,
    );
    if (!$row) {
        activation_json(404, ['error' => 'not_found']);
    }
    if (!field_orders_can_access_order($pdo, $ctx, $row)) {
        activation_json(403, ['error' => 'forbidden']);
    }
    $orderId = (string) $row['id'];
    $organizationId = trim((string) $row['organization_id']);
    $current = (string) $row['status'];
    if ($current !== 'pending') {
        activation_json(409, ['error' => 'already_reviewed', 'status' => $current]);
    }

    $rejectReason = trim((string) ($body['rejectReason'] ?? $body['reject_reason'] ?? ''));
    if ($newStatus === 'rejected' && $rejectReason === '') {
        activation_json(400, ['error' => 'reject_reason_required']);
    }

    $now = activation_now_iso();
    $lines = field_orders_fetch_lines($pdo, $orderId);
    try {
        $pdo->beginTransaction();
        $up = $pdo->prepare(
            'UPDATE field_orders SET
            status = ?,
            reject_reason = ?,
            reviewed_by_email = ?,
            reviewed_at = ?,
            updated_at = ?
         WHERE id = ?',
        );
        $up->execute([
            $newStatus,
            $newStatus === 'rejected' ? $rejectReason : null,
            $ctx['email'],
            $now,
            $now,
            $orderId,
        ]);
        if ($newStatus === 'approved') {
            require_once __DIR__ . '/field_truck_stock.php';
            field_truck_stock_deduct_for_order($pdo, $row, $lines);
        }
        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        error_log('[field_orders] review: ' . $e->getMessage());
        activation_json(500, ['error' => 'server_error']);
    }

    $row['status'] = $newStatus;
    $row['reject_reason'] = $newStatus === 'rejected' ? $rejectReason : null;
    $row['reviewed_by_email'] = $ctx['email'];
    $row['reviewed_at'] = $now;
    $row['updated_at'] = $now;
    $order = field_orders_row_to_public(
        $row,
        field_orders_fetch_lines($pdo, $orderId),
    );
    activation_json(200, ['ok' => true, 'order' => $order]);
}

/**
 * @return array<string,mixed>
 */
function field_orders_require_pending_for_distributor(
    PDO $pdo,
    array $ctx,
    array $body,
    string $organizationId,
): array {
    $orderId = trim((string) ($body['orderId'] ?? $body['id'] ?? ''));
    $clientOrderId = trim((string) ($body['clientOrderId'] ?? $body['client_order_id'] ?? ''));
    $row = field_orders_fetch_row_by_reference(
        $pdo,
        $orderId,
        $clientOrderId,
        $organizationId,
    );
    if (!$row) {
        activation_json(404, ['error' => 'not_found']);
    }
    if (!field_orders_can_access_order($pdo, $ctx, $row)) {
        activation_json(403, ['error' => 'forbidden']);
    }
    if ((string) $row['status'] !== 'pending') {
        activation_json(409, [
            'error' => 'already_reviewed',
            'status' => (string) $row['status'],
        ]);
    }
    $distributorUserId = trim((string) ($body['distributorUserId'] ?? $body['distributor_user_id'] ?? ''));
    $installationId = trim((string) ($body['installationId'] ?? $body['installation_id'] ?? ''));
    $rowDist = trim((string) ($row['distributor_user_id'] ?? ''));
    $rowInstall = trim((string) ($row['installation_id'] ?? ''));
    if ($distributorUserId !== '' && $rowDist !== '' && $rowDist !== $distributorUserId) {
        activation_json(403, ['error' => 'forbidden']);
    }
    if ($installationId !== '' && $rowInstall !== '' && $rowInstall !== $installationId) {
        activation_json(403, ['error' => 'forbidden']);
    }

    return $row;
}

function field_orders_handle_cancel(PDO $pdo, array $config): void
{
    $body = activation_json_body();
    $ctx = field_orders_require_distributor_cloud_context($pdo, $config, array_merge($_GET, $body));
    $organizationId = trim($ctx['organization_id']);
    $row = field_orders_require_pending_for_distributor($pdo, $ctx, $body, $organizationId);
    $orderId = (string) $row['id'];

    $pdo->prepare('DELETE FROM field_orders WHERE id = ?')->execute([$orderId]);
    activation_json(200, ['ok' => true, 'deleted' => true, 'id' => $orderId]);
}

function field_orders_handle_update(PDO $pdo, array $config): void
{
    $body = activation_json_body();
    $ctx = field_orders_require_distributor_cloud_context($pdo, $config, array_merge($_GET, $body));
    $organizationId = trim($ctx['organization_id']);
    $row = field_orders_require_pending_for_distributor($pdo, $ctx, $body, $organizationId);
    $orderId = (string) $row['id'];
    $organizationId = trim((string) $row['organization_id']);

    $customer = is_array($body['customer'] ?? null) ? $body['customer'] : [];
    $customerName = trim((string) ($customer['name'] ?? $body['customerName'] ?? ''));
    if ($customerName === '') {
        activation_json(400, ['error' => 'customer_required']);
    }

    $lines = field_orders_parse_lines(
        is_array($body['lines'] ?? null) ? $body['lines'] : [],
    );
    $payment = field_orders_parse_payment($body);
    $inventorySource = field_orders_parse_inventory_source($body);
    $now = activation_now_iso();

    try {
        $pdo->beginTransaction();
        $up = $pdo->prepare(
            'UPDATE field_orders SET
                customer_id = ?,
                customer_name = ?,
                customer_phone = ?,
                customer_address = ?,
                notes = ?,
                payment_type = ?,
                paid_amount = ?,
                discount_amount = ?,
                tax_percent = ?,
                grand_total = ?,
                payment_splits_json = ?,
                inventory_source = ?,
                updated_at = ?
             WHERE id = ?',
        );
        $up->execute([
            trim((string) ($customer['id'] ?? $body['customerId'] ?? '')) ?: null,
            $customerName,
            trim((string) ($customer['phone'] ?? '')) ?: null,
            trim((string) ($customer['address'] ?? '')) ?: null,
            trim((string) ($body['notes'] ?? '')) ?: null,
            $payment['payment_type'],
            $payment['paid_amount'],
            $payment['discount_amount'],
            $payment['tax_percent'],
            $payment['grand_total'],
            $payment['payment_splits_json'],
            $inventorySource,
            $now,
            $orderId,
        ]);
        $pdo->prepare('DELETE FROM field_order_lines WHERE field_order_id = ?')->execute([$orderId]);
        $lineIns = $pdo->prepare(
            'INSERT INTO field_order_lines (
                id, field_order_id, line_index,
                product_id, product_name, barcode, quantity, unit_price, unit_name
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        );
        foreach ($lines as $idx => $ln) {
            $lineIns->execute([
                activation_uuid(),
                $orderId,
                $idx,
                $ln['product_id'],
                $ln['product_name'],
                $ln['barcode'] !== '' ? $ln['barcode'] : null,
                $ln['quantity'],
                $ln['unit_price'],
                $ln['unit_name'] !== '' ? $ln['unit_name'] : null,
            ]);
        }
        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        error_log('[field_orders] update: ' . $e->getMessage());
        activation_json(500, ['error' => 'server']);
    }

    $order = field_orders_fetch_public($pdo, $orderId, $organizationId);
    if ($order === null) {
        activation_json(500, ['error' => 'server']);
    }
    activation_json(200, ['ok' => true, 'order' => $order]);
}

/**
 * يُرجع true إذا عُولج المسار.
 */
function field_orders_dispatch(PDO $pdo, array $config, string $method, string $path): bool
{
    field_orders_ensure_schema($pdo);

    if ($method === 'POST' && $path === '/api/field-orders') {
        field_orders_handle_create($pdo, $config);

        return true;
    }

    if ($method === 'GET' && $path === '/api/field-orders/pending') {
        field_orders_handle_list_pending($pdo, $config);

        return true;
    }

    if ($method === 'GET' && $path === '/api/field-orders/list') {
        field_orders_handle_list($pdo, $config);

        return true;
    }

    if ($method === 'POST' && $path === '/api/field-orders/review') {
        field_orders_handle_review($pdo, $config, '', 'from_body');

        return true;
    }

    if ($method === 'POST' && $path === '/api/field-orders/cancel') {
        field_orders_handle_cancel($pdo, $config);

        return true;
    }

    if ($method === 'POST' && $path === '/api/field-orders/update') {
        field_orders_handle_update($pdo, $config);

        return true;
    }

    if ($method === 'GET' && preg_match('#^/api/field-orders/([0-9a-fA-F-]{36})$#', $path, $m)) {
        field_orders_handle_get_one($pdo, $config, $m[1]);

        return true;
    }

    if ($method === 'POST' && preg_match('#^/api/field-orders/([0-9a-fA-F-]{36})/approve$#', $path, $m)) {
        field_orders_handle_review($pdo, $config, $m[1], 'approved');

        return true;
    }

    if ($method === 'POST' && preg_match('#^/api/field-orders/([0-9a-fA-F-]{36})/reject$#', $path, $m)) {
        field_orders_handle_review($pdo, $config, $m[1], 'rejected');

        return true;
    }

    return false;
}
