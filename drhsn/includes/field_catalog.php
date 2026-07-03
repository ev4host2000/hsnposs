<?php
declare(strict_types=1);

/**
 * كتالوج الميدان — نشر من الحاسوب وسحب على جوال الموزّع.
 * مسارات جديدة فقط؛ لا تغيّر تفعيل/قسائم المشتركين الحاليين.
 */

require_once __DIR__ . '/field_orders.php';
require_once __DIR__ . '/field_truck_stock.php';

function field_catalog_ensure_schema(PDO $pdo): void
{
    field_orders_ensure_schema($pdo);
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS field_catalog_meta (
            organization_id TEXT PRIMARY KEY,
            version TEXT NOT NULL,
            product_count INTEGER NOT NULL DEFAULT 0,
            published_by_email TEXT,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS field_catalog_products (
            id TEXT PRIMARY KEY,
            organization_id TEXT NOT NULL,
            product_id TEXT NOT NULL,
            product_name TEXT NOT NULL,
            barcode TEXT,
            sale_price REAL,
            unit_name TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0,
            stock_qty REAL
        );
        CREATE UNIQUE INDEX IF NOT EXISTS uq_field_catalog_org_product
            ON field_catalog_products(organization_id, product_id);
        CREATE INDEX IF NOT EXISTS idx_field_catalog_org_sort
            ON field_catalog_products(organization_id, sort_order, product_name);
        CREATE TABLE IF NOT EXISTS field_catalog_customers (
            id TEXT PRIMARY KEY,
            organization_id TEXT NOT NULL,
            customer_id TEXT NOT NULL,
            customer_name TEXT NOT NULL,
            phone TEXT,
            address TEXT,
            customer_number TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        CREATE UNIQUE INDEX IF NOT EXISTS uq_field_catalog_org_customer
            ON field_catalog_customers(organization_id, customer_id);
        CREATE INDEX IF NOT EXISTS idx_field_catalog_org_customer_sort
            ON field_catalog_customers(organization_id, sort_order, customer_name);
    ");
    try {
        $pdo->exec(
            'ALTER TABLE field_catalog_meta ADD COLUMN customer_count INTEGER NOT NULL DEFAULT 0',
        );
    } catch (Throwable $e) {
        /* العمود موجود */
    }
    try {
        $pdo->exec(
            'ALTER TABLE field_catalog_products ADD COLUMN stock_qty REAL',
        );
    } catch (Throwable $e) {
        /* العمود موجود */
    }
}

/** @return array<string,mixed>|null */
function field_catalog_fetch_meta(PDO $pdo, string $organizationId): ?array
{
    $st = $pdo->prepare(
        'SELECT * FROM field_catalog_meta WHERE trim(organization_id) = trim(?) LIMIT 1',
    );
    $st->execute([$organizationId]);
    $row = $st->fetch(PDO::FETCH_ASSOC);

    return $row === false ? null : $row;
}

/** @return list<array<string,mixed>> */
function field_catalog_fetch_products(PDO $pdo, string $organizationId): array
{
    $st = $pdo->prepare(
        'SELECT product_id, product_name, barcode, sale_price, unit_name, sort_order, stock_qty
         FROM field_catalog_products
         WHERE trim(organization_id) = trim(?)
         ORDER BY sort_order ASC, product_name COLLATE NOCASE ASC',
    );
    $st->execute([$organizationId]);
    $rows = $st->fetchAll(PDO::FETCH_ASSOC);
    $items = [];
    foreach ($rows as $row) {
        $items[] = [
            'productId' => (string) $row['product_id'],
            'productName' => (string) $row['product_name'],
            'barcode' => (string) ($row['barcode'] ?? ''),
            'salePrice' => $row['sale_price'] === null ? null : (float) $row['sale_price'],
            'unitName' => (string) ($row['unit_name'] ?? ''),
            'sortOrder' => (int) ($row['sort_order'] ?? 0),
            'stockQty' => $row['stock_qty'] === null ? null : (float) $row['stock_qty'],
        ];
    }

    return $items;
}

/** @return list<array<string,mixed>> */
function field_catalog_fetch_customers(PDO $pdo, string $organizationId): array
{
    $st = $pdo->prepare(
        'SELECT customer_id, customer_name, phone, address, customer_number, sort_order
         FROM field_catalog_customers
         WHERE trim(organization_id) = trim(?)
         ORDER BY sort_order ASC, customer_name COLLATE NOCASE ASC',
    );
    $st->execute([$organizationId]);
    $rows = $st->fetchAll(PDO::FETCH_ASSOC);
    $items = [];
    foreach ($rows as $row) {
        $items[] = [
            'customerId' => (string) $row['customer_id'],
            'customerName' => (string) $row['customer_name'],
            'phone' => (string) ($row['phone'] ?? ''),
            'address' => (string) ($row['address'] ?? ''),
            'customerNumber' => (string) ($row['customer_number'] ?? ''),
            'sortOrder' => (int) ($row['sort_order'] ?? 0),
        ];
    }

    return $items;
}

/** @param list<array<string,mixed>> $rawProducts */
function field_catalog_parse_products(array $rawProducts): array
{
    $items = [];
    $index = 0;
    foreach ($rawProducts as $raw) {
        if (!is_array($raw)) {
            continue;
        }
        $productId = trim((string) ($raw['productId'] ?? $raw['product_id'] ?? $raw['id'] ?? ''));
        $productName = trim((string) ($raw['productName'] ?? $raw['product_name'] ?? $raw['name'] ?? ''));
        if ($productId === '' || $productName === '') {
            continue;
        }
        $barcode = trim((string) ($raw['barcode'] ?? ''));
        $unitName = trim((string) ($raw['unitName'] ?? $raw['unit_name'] ?? ''));
        $salePrice = $raw['salePrice'] ?? $raw['sale_price'] ?? null;
        $sale = null;
        if ($salePrice !== null && $salePrice !== '') {
            $sale = (float) $salePrice;
        }
        $sortOrder = (int) ($raw['sortOrder'] ?? $raw['sort_order'] ?? $index);
        $stockRaw = $raw['stockQty'] ?? $raw['stock_qty'] ?? null;
        $stock = null;
        if ($stockRaw !== null && $stockRaw !== '') {
            $stock = (float) $stockRaw;
            if (!is_finite($stock)) {
                $stock = null;
            }
        }
        $items[] = [
            'product_id' => $productId,
            'product_name' => $productName,
            'barcode' => $barcode,
            'sale_price' => $sale,
            'unit_name' => $unitName,
            'sort_order' => $sortOrder,
            'stock_qty' => $stock,
        ];
        $index++;
    }

    return $items;
}

/** @param list<array<string,mixed>> $rawCustomers */
function field_catalog_parse_customers(array $rawCustomers): array
{
    $items = [];
    $index = 0;
    foreach ($rawCustomers as $raw) {
        if (!is_array($raw)) {
            continue;
        }
        $customerId = trim((string) ($raw['customerId'] ?? $raw['customer_id'] ?? $raw['id'] ?? ''));
        $customerName = trim((string) ($raw['customerName'] ?? $raw['customer_name'] ?? $raw['name'] ?? ''));
        if ($customerId === '' || $customerName === '') {
            continue;
        }
        $items[] = [
            'customer_id' => $customerId,
            'customer_name' => $customerName,
            'phone' => trim((string) ($raw['phone'] ?? '')),
            'address' => trim((string) ($raw['address'] ?? '')),
            'customer_number' => trim((string) ($raw['customerNumber'] ?? $raw['customer_number'] ?? '')),
            'sort_order' => (int) ($raw['sortOrder'] ?? $raw['sort_order'] ?? $index),
        ];
        $index++;
    }

    return $items;
}

function field_catalog_handle_publish(PDO $pdo, array $config): void
{
    $body = activation_json_body();
    $ctx = field_orders_require_distributor_cloud_context($pdo, $config, $body);
    $organizationId = $ctx['organization_id'];

    $rawProducts = $body['products'] ?? [];
    if (!is_array($rawProducts)) {
        activation_json(400, ['error' => 'validation']);
    }
    $rawCustomers = $body['customers'] ?? [];
    if (!is_array($rawCustomers)) {
        activation_json(400, ['error' => 'validation']);
    }
    $products = field_catalog_parse_products($rawProducts);
    $customers = field_catalog_parse_customers($rawCustomers);
    if (count($products) > 5000 || count($customers) > 5000) {
        activation_json(400, ['error' => 'too_many_items']);
    }
    distributor_license_enforce_trial_product_count(
        $pdo,
        $organizationId,
        count($products),
    );

    $now = activation_now_iso();
    $version = $now;

    try {
        $pdo->beginTransaction();
        $pdo->prepare('DELETE FROM field_catalog_products WHERE trim(organization_id) = trim(?)')
            ->execute([$organizationId]);
        $pdo->prepare('DELETE FROM field_catalog_customers WHERE trim(organization_id) = trim(?)')
            ->execute([$organizationId]);
        $ins = $pdo->prepare(
            'INSERT INTO field_catalog_products (
                id, organization_id, product_id, product_name, barcode, sale_price, unit_name, sort_order, stock_qty
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        );
        foreach ($products as $p) {
            $ins->execute([
                activation_uuid(),
                $organizationId,
                $p['product_id'],
                $p['product_name'],
                $p['barcode'] !== '' ? $p['barcode'] : null,
                $p['sale_price'],
                $p['unit_name'] !== '' ? $p['unit_name'] : null,
                $p['sort_order'],
                $p['stock_qty'] ?? null,
            ]);
        }
        $insCust = $pdo->prepare(
            'INSERT INTO field_catalog_customers (
                id, organization_id, customer_id, customer_name, phone, address, customer_number, sort_order
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        );
        foreach ($customers as $c) {
            $insCust->execute([
                activation_uuid(),
                $organizationId,
                $c['customer_id'],
                $c['customer_name'],
                $c['phone'] !== '' ? $c['phone'] : null,
                $c['address'] !== '' ? $c['address'] : null,
                $c['customer_number'] !== '' ? $c['customer_number'] : null,
                $c['sort_order'],
            ]);
        }
        $pdo->prepare(
            'INSERT INTO field_catalog_meta (
                organization_id, version, product_count, customer_count, published_by_email, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?)
             ON CONFLICT(organization_id) DO UPDATE SET
                version = excluded.version,
                product_count = excluded.product_count,
                customer_count = excluded.customer_count,
                published_by_email = excluded.published_by_email,
                updated_at = excluded.updated_at',
        )->execute([
            $organizationId,
            $version,
            count($products),
            count($customers),
            $ctx['email'],
            $now,
        ]);
        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        error_log('[field_catalog] publish: ' . $e->getMessage());
        activation_json(500, ['error' => 'server_error']);
    }

    activation_json(200, [
        'ok' => true,
        'version' => $version,
        'productCount' => count($products),
        'customerCount' => count($customers),
        'publishedAt' => $now,
    ]);
}

function field_catalog_handle_get(PDO $pdo, array $config): void
{
    $ctx = field_orders_require_distributor_cloud_context($pdo, $config, $_GET);
    $organizationId = $ctx['organization_id'];
    $sinceVersion = trim((string) ($_GET['sinceVersion'] ?? $_GET['since_version'] ?? ''));

    $meta = field_catalog_fetch_meta($pdo, $organizationId);
    if ($meta === null) {
        activation_json(200, [
            'ok' => true,
            'version' => null,
            'productCount' => 0,
            'customerCount' => 0,
            'products' => [],
            'customers' => [],
        ]);
    }

    $version = (string) $meta['version'];
    if ($sinceVersion !== '' && $sinceVersion === $version) {
        activation_json(200, [
            'ok' => true,
            'unchanged' => true,
            'version' => $version,
            'productCount' => (int) ($meta['product_count'] ?? 0),
            'customerCount' => (int) ($meta['customer_count'] ?? 0),
            'publishedAt' => (string) ($meta['updated_at'] ?? ''),
        ]);
    }

    $products = field_catalog_fetch_products($pdo, $organizationId);
    $customers = field_catalog_fetch_customers($pdo, $organizationId);
    activation_json(200, [
        'ok' => true,
        'unchanged' => false,
        'version' => $version,
        'productCount' => count($products),
        'customerCount' => count($customers),
        'publishedAt' => (string) ($meta['updated_at'] ?? ''),
        'publishedByEmail' => (string) ($meta['published_by_email'] ?? ''),
        'products' => $products,
        'customers' => $customers,
    ]);
}

function field_catalog_dispatch(PDO $pdo, array $config, string $method, string $path): bool
{
    field_catalog_ensure_schema($pdo);

    if ($method === 'POST' && $path === '/api/field-catalog/publish') {
        field_catalog_handle_publish($pdo, $config);

        return true;
    }

    if ($method === 'GET' && $path === '/api/field-catalog') {
        field_catalog_handle_get($pdo, $config);

        return true;
    }

    return false;
}
