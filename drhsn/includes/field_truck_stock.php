<?php
declare(strict_types=1);

/**
 * مخزون شاحنة الموزّع — تحميل من الحاسوب وسحب على الجوال.
 */

require_once __DIR__ . '/field_orders.php';
require_once __DIR__ . '/team_users.php';

function field_truck_stock_ensure_schema(PDO $pdo): void
{
    field_orders_ensure_schema($pdo);
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS field_truck_stock_meta (
            organization_id TEXT NOT NULL,
            distributor_user_id TEXT NOT NULL,
            version TEXT NOT NULL,
            item_count INTEGER NOT NULL DEFAULT 0,
            updated_by_email TEXT,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (organization_id, distributor_user_id)
        );
        CREATE TABLE IF NOT EXISTS field_truck_stock_items (
            id TEXT PRIMARY KEY,
            organization_id TEXT NOT NULL,
            distributor_user_id TEXT NOT NULL,
            product_id TEXT NOT NULL,
            product_name TEXT NOT NULL,
            barcode TEXT,
            sale_price REAL,
            unit_name TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0,
            qty REAL NOT NULL DEFAULT 0
        );
        CREATE UNIQUE INDEX IF NOT EXISTS uq_field_truck_stock_org_dist_product
            ON field_truck_stock_items(organization_id, distributor_user_id, product_id);
        CREATE INDEX IF NOT EXISTS idx_field_truck_stock_org_dist_sort
            ON field_truck_stock_items(organization_id, distributor_user_id, sort_order, product_name);
    ");
}

/** @param list<array<string,mixed>> $rawItems */
function field_truck_stock_parse_items(array $rawItems): array
{
    $items = [];
    $index = 0;
    foreach ($rawItems as $raw) {
        if (!is_array($raw)) {
            continue;
        }
        $productId = trim((string) ($raw['productId'] ?? $raw['product_id'] ?? $raw['id'] ?? ''));
        $productName = trim((string) ($raw['productName'] ?? $raw['product_name'] ?? $raw['name'] ?? ''));
        if ($productId === '' || $productName === '') {
            continue;
        }
        $qtyRaw = $raw['qty'] ?? $raw['quantity'] ?? $raw['stockQty'] ?? 0;
        $qty = (float) $qtyRaw;
        if (!is_finite($qty) || $qty < 0) {
            $qty = 0.0;
        }
        $salePrice = $raw['salePrice'] ?? $raw['sale_price'] ?? null;
        $sale = null;
        if ($salePrice !== null && $salePrice !== '') {
            $sale = (float) $salePrice;
        }
        $items[] = [
            'product_id' => $productId,
            'product_name' => $productName,
            'barcode' => trim((string) ($raw['barcode'] ?? '')),
            'sale_price' => $sale,
            'unit_name' => trim((string) ($raw['unitName'] ?? $raw['unit_name'] ?? '')),
            'sort_order' => (int) ($raw['sortOrder'] ?? $raw['sort_order'] ?? $index),
            'qty' => $qty,
        ];
        $index++;
    }

    return $items;
}

/** @return list<array<string,mixed>> */
function field_truck_stock_fetch_items(
    PDO $pdo,
    string $organizationId,
    string $distributorUserId,
): array {
    $st = $pdo->prepare(
        'SELECT product_id, product_name, barcode, sale_price, unit_name, sort_order, qty
         FROM field_truck_stock_items
         WHERE trim(organization_id) = trim(?)
           AND trim(distributor_user_id) = trim(?)
           AND qty > 0
         ORDER BY sort_order ASC, product_name COLLATE NOCASE ASC',
    );
    $st->execute([$organizationId, $distributorUserId]);
    $out = [];
    foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $out[] = [
            'productId' => (string) $row['product_id'],
            'productName' => (string) $row['product_name'],
            'barcode' => (string) ($row['barcode'] ?? ''),
            'salePrice' => $row['sale_price'] === null ? null : (float) $row['sale_price'],
            'unitName' => (string) ($row['unit_name'] ?? ''),
            'sortOrder' => (int) ($row['sort_order'] ?? 0),
            'qty' => (float) ($row['qty'] ?? 0),
        ];
    }

    return $out;
}

function field_truck_stock_handle_publish(PDO $pdo, array $config): void
{
    $body = activation_json_body();
    $ctx = field_orders_require_distributor_cloud_context($pdo, $config, $body);
    $organizationId = $ctx['organization_id'];
    $distributorUserId = trim((string) (
        $body['distributorUserId'] ?? $body['distributor_user_id'] ?? ''
    ));
    if ($distributorUserId === '') {
        activation_json(400, ['error' => 'validation']);
    }

    $rawItems = $body['items'] ?? [];
    if (!is_array($rawItems)) {
        activation_json(400, ['error' => 'validation']);
    }
    $items = field_truck_stock_parse_items($rawItems);
    $activeCount = count(array_filter(
        $items,
        static fn (array $i): bool => ($i['qty'] ?? 0) > 1e-9,
    ));
    distributor_license_enforce_trial_product_count(
        $pdo,
        $organizationId,
        $activeCount,
    );
    $now = activation_now_iso();
    $version = activation_uuid();

    try {
        $pdo->beginTransaction();
        $pdo->prepare(
            'DELETE FROM field_truck_stock_items
             WHERE trim(organization_id) = trim(?) AND trim(distributor_user_id) = trim(?)',
        )->execute([$organizationId, $distributorUserId]);

        $ins = $pdo->prepare(
            'INSERT INTO field_truck_stock_items (
                id, organization_id, distributor_user_id,
                product_id, product_name, barcode, sale_price, unit_name, sort_order, qty
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        );
        foreach ($items as $item) {
            if ($item['qty'] <= 1e-9) {
                continue;
            }
            $ins->execute([
                activation_uuid(),
                $organizationId,
                $distributorUserId,
                $item['product_id'],
                $item['product_name'],
                $item['barcode'],
                $item['sale_price'],
                $item['unit_name'],
                $item['sort_order'],
                $item['qty'],
            ]);
        }

        $pdo->prepare(
            'INSERT INTO field_truck_stock_meta (
                organization_id, distributor_user_id, version, item_count, updated_by_email, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(organization_id, distributor_user_id) DO UPDATE SET
                version = excluded.version,
                item_count = excluded.item_count,
                updated_by_email = excluded.updated_by_email,
                updated_at = excluded.updated_at',
        )->execute([
            $organizationId,
            $distributorUserId,
            $version,
            count(array_filter($items, static fn (array $i): bool => $i['qty'] > 1e-9)),
            $ctx['email'],
            $now,
        ]);
        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        error_log('[field_truck_stock] publish: ' . $e->getMessage());
        activation_json(500, ['error' => 'server_error']);
    }

    activation_json(200, [
        'ok' => true,
        'version' => $version,
        'itemCount' => count(array_filter($items, static fn (array $i): bool => $i['qty'] > 1e-9)),
        'updatedAt' => $now,
    ]);
}

/** @return list<string> */
function field_truck_stock_distributor_id_candidates(
    PDO $pdo,
    string $organizationId,
    string $distributorUserId,
    string $distributorUsername,
): array {
    $candidates = [];
    $add = static function (string $id) use (&$candidates): void {
        $t = trim($id);
        if ($t !== '' && !in_array($t, $candidates, true)) {
            $candidates[] = $t;
        }
    };

    $add($distributorUserId);

    $username = strtolower(trim($distributorUsername));
    if ($username === '') {
        return $candidates;
    }

    team_users_ensure_schema($pdo);
    $st = $pdo->prepare(
        "SELECT user_id FROM team_users
         WHERE trim(organization_id) = trim(?)
           AND deleted = 0
           AND lower(trim(role)) = 'distributor'
           AND (
             lower(trim(username)) = ?
             OR lower(trim(email)) = ?
           )
         ORDER BY updated_at DESC",
    );
    $st->execute([$organizationId, $username, $username]);
    foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $add((string) ($row['user_id'] ?? ''));
    }

    return $candidates;
}

function field_truck_stock_resolve_distributor_id(
    PDO $pdo,
    string $organizationId,
    string $distributorUserId,
    string $distributorUsername,
): string {
    foreach (
        field_truck_stock_distributor_id_candidates(
            $pdo,
            $organizationId,
            $distributorUserId,
            $distributorUsername,
        ) as $candidate
    ) {
        $st = $pdo->prepare(
            'SELECT 1 FROM field_truck_stock_meta
             WHERE trim(organization_id) = trim(?)
               AND trim(distributor_user_id) = trim(?)
             LIMIT 1',
        );
        $st->execute([$organizationId, $candidate]);
        if ($st->fetchColumn()) {
            return $candidate;
        }
        $st2 = $pdo->prepare(
            'SELECT 1 FROM field_truck_stock_items
             WHERE trim(organization_id) = trim(?)
               AND trim(distributor_user_id) = trim(?)
               AND qty > 0
             LIMIT 1',
        );
        $st2->execute([$organizationId, $candidate]);
        if ($st2->fetchColumn()) {
            return $candidate;
        }
    }

    $fallback = trim($distributorUserId);
    if ($fallback !== '') {
        return $fallback;
    }
    $candidates = field_truck_stock_distributor_id_candidates(
        $pdo,
        $organizationId,
        $distributorUserId,
        $distributorUsername,
    );

    return $candidates[0] ?? '';
}

function field_truck_stock_handle_get(PDO $pdo, array $config): void
{
    $ctx = field_orders_require_distributor_cloud_context($pdo, $config, $_GET);
    $organizationId = $ctx['organization_id'];
    $distributorUserId = trim((string) (
        $_GET['distributorUserId'] ?? $_GET['distributor_user_id'] ?? ''
    ));
    $distributorUsername = trim((string) (
        $_GET['distributorUsername'] ?? $_GET['distributor_username'] ?? ''
    ));
    if ($distributorUserId === '' && $distributorUsername === '') {
        activation_json(400, ['error' => 'validation']);
    }
    $distributorUserId = field_truck_stock_resolve_distributor_id(
        $pdo,
        $organizationId,
        $distributorUserId,
        $distributorUsername,
    );
    if ($distributorUserId === '') {
        activation_json(400, ['error' => 'validation']);
    }
    $sinceVersion = trim((string) ($_GET['sinceVersion'] ?? $_GET['since_version'] ?? ''));

    $st = $pdo->prepare(
        'SELECT * FROM field_truck_stock_meta
         WHERE trim(organization_id) = trim(?) AND trim(distributor_user_id) = trim(?)
         LIMIT 1',
    );
    $st->execute([$organizationId, $distributorUserId]);
    $meta = $st->fetch(PDO::FETCH_ASSOC);
    if ($meta === false) {
        activation_json(200, [
            'ok' => true,
            'version' => null,
            'itemCount' => 0,
            'items' => [],
        ]);
    }

    $updatedBy = strtolower(trim((string) ($meta['updated_by_email'] ?? '')));
    $ctxEmail = strtolower(trim((string) ($ctx['email'] ?? '')));
    if ($updatedBy !== '' && $ctxEmail !== '' && $updatedBy !== $ctxEmail) {
        activation_json(200, [
            'ok' => true,
            'version' => null,
            'itemCount' => 0,
            'items' => [],
        ]);
    }

    $version = (string) $meta['version'];
    if ($sinceVersion !== '' && $sinceVersion === $version) {
        activation_json(200, [
            'ok' => true,
            'unchanged' => true,
            'version' => $version,
            'itemCount' => (int) ($meta['item_count'] ?? 0),
            'updatedAt' => (string) ($meta['updated_at'] ?? ''),
        ]);
    }

    $items = field_truck_stock_fetch_items($pdo, $organizationId, $distributorUserId);
    activation_json(200, [
        'ok' => true,
        'unchanged' => false,
        'version' => $version,
        'itemCount' => count($items),
        'updatedAt' => (string) ($meta['updated_at'] ?? ''),
        'items' => $items,
    ]);
}

/** خصم كميات الطلب من مخزون الشاحنة عند الاعتماد. */
function field_truck_stock_deduct_for_order(PDO $pdo, array $orderRow, array $lines): void
{
    $source = strtolower(trim((string) ($orderRow['inventory_source'] ?? 'main')));
    if ($source !== 'truck') {
        return;
    }
    $organizationId = trim((string) ($orderRow['organization_id'] ?? ''));
    $distributorUserId = trim((string) ($orderRow['distributor_user_id'] ?? ''));
    if ($organizationId === '' || $distributorUserId === '') {
        return;
    }

    $upd = $pdo->prepare(
        'UPDATE field_truck_stock_items
         SET qty = MAX(0, qty - ?)
         WHERE trim(organization_id) = trim(?)
           AND trim(distributor_user_id) = trim(?)
           AND trim(product_id) = trim(?)',
    );
    foreach ($lines as $ln) {
        $productId = trim((string) ($ln['product_id'] ?? $ln['productId'] ?? ''));
        $qty = (float) ($ln['quantity'] ?? 0);
        if ($productId === '' || $qty <= 1e-9) {
            continue;
        }
        $upd->execute([$qty, $organizationId, $distributorUserId, $productId]);
    }

    $pdo->prepare(
        'DELETE FROM field_truck_stock_items
         WHERE trim(organization_id) = trim(?)
           AND trim(distributor_user_id) = trim(?)
           AND qty <= 1e-9',
    )->execute([$organizationId, $distributorUserId]);

    $version = activation_uuid();
    $now = activation_now_iso();
    $countSt = $pdo->prepare(
        'SELECT COUNT(*) FROM field_truck_stock_items
         WHERE trim(organization_id) = trim(?) AND trim(distributor_user_id) = trim(?)',
    );
    $countSt->execute([$organizationId, $distributorUserId]);
    $itemCount = (int) ($countSt->fetchColumn() ?: 0);

    $pdo->prepare(
        'INSERT INTO field_truck_stock_meta (
            organization_id, distributor_user_id, version, item_count, updated_at
        ) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(organization_id, distributor_user_id) DO UPDATE SET
            version = excluded.version,
            item_count = excluded.item_count,
            updated_at = excluded.updated_at',
    )->execute([$organizationId, $distributorUserId, $version, $itemCount, $now]);
}

function field_truck_stock_dispatch(PDO $pdo, array $config, string $method, string $path): bool
{
    field_truck_stock_ensure_schema($pdo);

    if ($method === 'POST' && $path === '/api/field-truck-stock/publish') {
        field_truck_stock_handle_publish($pdo, $config);

        return true;
    }

    if ($method === 'GET' && $path === '/api/field-truck-stock') {
        field_truck_stock_handle_get($pdo, $config);

        return true;
    }

    return false;
}
