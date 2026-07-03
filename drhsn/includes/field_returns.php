<?php
declare(strict_types=1);

require_once __DIR__ . '/field_orders.php';

/** @return list<string> */
function field_returns_valid_statuses(): array
{
    return ['pending', 'approved', 'rejected'];
}

function field_returns_ensure_schema(PDO $pdo): void
{
    field_orders_ensure_schema($pdo);
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS field_returns (
            id TEXT PRIMARY KEY,
            organization_id TEXT NOT NULL,
            client_return_id TEXT,
            field_order_id TEXT NOT NULL,
            client_order_id TEXT,
            status TEXT NOT NULL DEFAULT 'pending',
            submitter_email TEXT NOT NULL,
            submitter_name TEXT,
            distributor_user_id TEXT,
            distributor_display_name TEXT,
            installation_id TEXT,
            notes TEXT,
            reject_reason TEXT,
            reviewed_by_email TEXT,
            reviewed_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE UNIQUE INDEX IF NOT EXISTS uq_field_returns_client
            ON field_returns(organization_id, client_return_id)
            WHERE client_return_id IS NOT NULL AND trim(client_return_id) <> '';
        CREATE INDEX IF NOT EXISTS idx_field_returns_org_status_created
            ON field_returns(organization_id, status, created_at DESC);
        CREATE TABLE IF NOT EXISTS field_return_lines (
            id TEXT PRIMARY KEY,
            field_return_id TEXT NOT NULL,
            line_index INTEGER NOT NULL,
            product_id TEXT,
            product_name TEXT NOT NULL,
            barcode TEXT,
            quantity REAL NOT NULL,
            unit_price REAL,
            unit_name TEXT,
            FOREIGN KEY (field_return_id) REFERENCES field_returns(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_field_return_lines_return
            ON field_return_lines(field_return_id, line_index);
    ");
}

/** @return array<string,mixed>|null */
function field_returns_fetch_row_by_reference(
    PDO $pdo,
    string $returnId,
    string $clientReturnId,
    string $organizationId,
): ?array {
    $returnId = trim($returnId);
    if ($returnId !== '') {
        $st = $pdo->prepare('SELECT * FROM field_returns WHERE id = ? LIMIT 1');
        $st->execute([$returnId]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if ($row) {
            return $row;
        }
    }
    $clientReturnId = trim($clientReturnId);
    $organizationId = trim($organizationId);
    if ($clientReturnId !== '' && $organizationId !== '') {
        $st = $pdo->prepare(
            'SELECT * FROM field_returns
             WHERE trim(organization_id) = trim(?) AND client_return_id = ?
             LIMIT 1',
        );
        $st->execute([$organizationId, $clientReturnId]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if ($row) {
            return $row;
        }
    }

    return null;
}

/** @return array<int,array<string,mixed>> */
function field_returns_fetch_lines(PDO $pdo, string $returnId): array
{
    $st = $pdo->prepare(
        'SELECT * FROM field_return_lines WHERE field_return_id = ? ORDER BY line_index ASC',
    );
    $st->execute([$returnId]);
    $rows = $st->fetchAll(PDO::FETCH_ASSOC);
    $out = [];
    foreach ($rows as $row) {
        $out[] = [
            'id' => (string) $row['id'],
            'lineIndex' => (int) $row['line_index'],
            'productId' => (string) ($row['product_id'] ?? ''),
            'productName' => (string) $row['product_name'],
            'barcode' => (string) ($row['barcode'] ?? ''),
            'quantity' => (float) $row['quantity'],
            'unitPrice' => isset($row['unit_price']) ? (float) $row['unit_price'] : null,
            'unitName' => (string) ($row['unit_name'] ?? ''),
        ];
    }

    return $out;
}

/** @param array<string,mixed> $row */
function field_returns_row_to_public(array $row, array $lines): array
{
    return [
        'id' => (string) $row['id'],
        'organizationId' => (string) $row['organization_id'],
        'clientReturnId' => (string) ($row['client_return_id'] ?? ''),
        'fieldOrderId' => (string) $row['field_order_id'],
        'clientOrderId' => (string) ($row['client_order_id'] ?? ''),
        'status' => (string) $row['status'],
        'submitterEmail' => (string) $row['submitter_email'],
        'submitterName' => (string) ($row['submitter_name'] ?? ''),
        'distributorUserId' => (string) ($row['distributor_user_id'] ?? ''),
        'distributorDisplayName' => (string) ($row['distributor_display_name'] ?? ''),
        'installationId' => (string) ($row['installation_id'] ?? ''),
        'notes' => (string) ($row['notes'] ?? ''),
        'rejectReason' => (string) ($row['reject_reason'] ?? ''),
        'reviewedByEmail' => (string) ($row['reviewed_by_email'] ?? ''),
        'reviewedAt' => (string) ($row['reviewed_at'] ?? ''),
        'createdAt' => (string) $row['created_at'],
        'updatedAt' => (string) $row['updated_at'],
        'lines' => $lines,
    ];
}

function field_returns_fetch_public(PDO $pdo, string $returnId, string $organizationId): ?array
{
    $st = $pdo->prepare(
        'SELECT * FROM field_returns WHERE id = ? AND trim(organization_id) = trim(?) LIMIT 1',
    );
    $st->execute([$returnId, $organizationId]);
    $row = $st->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return null;
    }

    return field_returns_row_to_public(
        $row,
        field_returns_fetch_lines($pdo, (string) $row['id']),
    );
}

function field_returns_can_access(PDO $pdo, array $ctx, array $row): bool
{
    return field_orders_can_access_order($pdo, $ctx, $row);
}

/** @param array<string,mixed> $body */
function field_returns_handle_create(PDO $pdo, array $config): void
{
    $body = activation_json_body();
    $ctx = field_orders_require_distributor_cloud_context($pdo, $config, $body);

    $organizationId = $ctx['organization_id'];
    $clientReturnId = trim((string) ($body['clientReturnId'] ?? $body['client_return_id'] ?? ''));
    if ($clientReturnId !== '') {
        $dup = $pdo->prepare(
            'SELECT id FROM field_returns
             WHERE trim(organization_id) = trim(?) AND client_return_id = ? LIMIT 1',
        );
        $dup->execute([$organizationId, $clientReturnId]);
        $existingId = (string) ($dup->fetchColumn() ?: '');
        if ($existingId !== '') {
            $ret = field_returns_fetch_public($pdo, $existingId, $organizationId);
            activation_json(200, ['ok' => true, 'duplicate' => true, 'fieldReturn' => $ret]);
        }
    }

    $fieldOrderId = trim((string) ($body['fieldOrderId'] ?? $body['field_order_id'] ?? ''));
    $clientOrderId = trim((string) ($body['clientOrderId'] ?? $body['client_order_id'] ?? ''));
    $orderRow = field_orders_fetch_row_by_reference(
        $pdo,
        $fieldOrderId,
        $clientOrderId,
        $organizationId,
    );
    if (!$orderRow) {
        activation_json(404, ['error' => 'order_not_found']);
    }
    if ((string) $orderRow['status'] !== 'approved') {
        activation_json(409, ['error' => 'order_not_approved']);
    }
    if (!field_orders_can_access_order($pdo, $ctx, $orderRow)) {
        activation_json(403, ['error' => 'forbidden']);
    }

    $lines = field_orders_parse_lines(
        is_array($body['lines'] ?? null) ? $body['lines'] : [],
    );
    if ($lines === []) {
        activation_json(400, ['error' => 'lines_required']);
    }

    $orderLines = field_orders_fetch_lines($pdo, (string) $orderRow['id']);
    $soldByProduct = [];
    foreach ($orderLines as $ol) {
        $pid = (string) ($ol['product_id'] ?? '');
        if ($pid === '') {
            continue;
        }
        $soldByProduct[$pid] = ($soldByProduct[$pid] ?? 0) + (float) $ol['quantity'];
    }
    foreach ($lines as $ln) {
        $pid = (string) ($ln['product_id'] ?? '');
        $qty = (float) $ln['quantity'];
        if ($pid === '' || $qty <= 0) {
            activation_json(400, ['error' => 'lines_required']);
        }
        if (!isset($soldByProduct[$pid]) || $qty > $soldByProduct[$pid] + 1e-9) {
            activation_json(400, ['error' => 'return_qty_exceeds_sale']);
        }
    }

    $now = activation_now_iso();
    $returnId = activation_uuid();
    $distributorUserId = trim((string) ($body['distributorUserId'] ?? $orderRow['distributor_user_id'] ?? ''));
    $distributorDisplayName = trim((string) (
        $body['distributorDisplayName'] ?? $orderRow['distributor_display_name'] ?? $ctx['full_name']
    ));
    $installationId = trim((string) ($body['installationId'] ?? $orderRow['installation_id'] ?? ''));

    try {
        $pdo->beginTransaction();
        $ins = $pdo->prepare(
            'INSERT INTO field_returns (
                id, organization_id, client_return_id,
                field_order_id, client_order_id, status,
                submitter_email, submitter_name,
                distributor_user_id, distributor_display_name, installation_id,
                notes, reject_reason, reviewed_by_email, reviewed_at,
                created_at, updated_at
            ) VALUES (
                ?, ?, ?,
                ?, ?, \'pending\',
                ?, ?,
                ?, ?, ?,
                ?, NULL, NULL, NULL,
                ?, ?
            )',
        );
        $ins->execute([
            $returnId,
            $organizationId,
            $clientReturnId !== '' ? $clientReturnId : null,
            (string) $orderRow['id'],
            (string) ($orderRow['client_order_id'] ?? ''),
            $ctx['email'],
            $ctx['full_name'],
            $distributorUserId !== '' ? $distributorUserId : null,
            $distributorDisplayName !== '' ? $distributorDisplayName : null,
            $installationId !== '' ? $installationId : null,
            trim((string) ($body['notes'] ?? '')) ?: null,
            $now,
            $now,
        ]);
        $lineIns = $pdo->prepare(
            'INSERT INTO field_return_lines (
                id, field_return_id, line_index,
                product_id, product_name, barcode, quantity, unit_price, unit_name
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        );
        foreach ($lines as $idx => $ln) {
            $lineIns->execute([
                activation_uuid(),
                $returnId,
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
        error_log('[field_returns] create: ' . $e->getMessage());
        activation_json(500, ['error' => 'server']);
    }

    $ret = field_returns_fetch_public($pdo, $returnId, $organizationId);
    activation_json(201, ['ok' => true, 'fieldReturn' => $ret]);
}

function field_returns_handle_list_pending(PDO $pdo, array $config): void
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
        'SELECT * FROM field_returns
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
        $items[] = field_returns_row_to_public(
            $row,
            field_returns_fetch_lines($pdo, (string) $row['id']),
        );
    }

    activation_json(200, ['ok' => true, 'items' => $items, 'count' => count($items)]);
}

function field_returns_handle_list(PDO $pdo, array $config): void
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

    $sql = 'SELECT * FROM field_returns WHERE trim(organization_id) = trim(?)';
    $args = [$organizationId];
    if ($installationId !== '') {
        $sql .= ' AND installation_id = ?';
        $args[] = $installationId;
    }
    if (in_array($statusFilter, field_returns_valid_statuses(), true)) {
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
        $items[] = field_returns_row_to_public(
            $row,
            field_returns_fetch_lines($pdo, (string) $row['id']),
        );
    }

    activation_json(200, ['ok' => true, 'items' => $items, 'count' => count($items)]);
}

function field_returns_handle_review(PDO $pdo, array $config, string $returnId, string $newStatus): void
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
        $returnId = trim((string) ($body['returnId'] ?? $body['id'] ?? ''));
    }
    if (!in_array($newStatus, ['approved', 'rejected'], true)) {
        activation_json(400, ['error' => 'validation']);
    }
    $ctx = field_orders_require_distributor_cloud_context($pdo, $config, array_merge($_GET, $body));
    $organizationId = trim($ctx['organization_id']);
    $clientReturnId = trim((string) (
        $body['clientReturnId'] ?? $body['client_return_id'] ?? $_GET['clientReturnId'] ?? ''
    ));

    $row = field_returns_fetch_row_by_reference(
        $pdo,
        $returnId,
        $clientReturnId,
        $organizationId,
    );
    if (!$row) {
        activation_json(404, ['error' => 'not_found']);
    }
    if (!field_returns_can_access($pdo, $ctx, $row)) {
        activation_json(403, ['error' => 'forbidden']);
    }
    $returnId = (string) $row['id'];
    if ((string) $row['status'] !== 'pending') {
        activation_json(409, ['error' => 'already_reviewed', 'status' => (string) $row['status']]);
    }

    $rejectReason = trim((string) ($body['rejectReason'] ?? $body['reject_reason'] ?? ''));
    if ($newStatus === 'rejected' && $rejectReason === '') {
        activation_json(400, ['error' => 'reject_reason_required']);
    }

    $now = activation_now_iso();
    try {
        $up = $pdo->prepare(
            'UPDATE field_returns SET
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
            $returnId,
        ]);
    } catch (Throwable $e) {
        error_log('[field_returns] review: ' . $e->getMessage());
        activation_json(500, ['error' => 'server']);
    }

    $updated = field_returns_fetch_row_by_reference($pdo, $returnId, '', $organizationId);
    if (!$updated) {
        activation_json(500, ['error' => 'server']);
    }
    $ret = field_returns_row_to_public(
        $updated,
        field_returns_fetch_lines($pdo, $returnId),
    );
    activation_json(200, ['ok' => true, 'fieldReturn' => $ret]);
}

function field_returns_dispatch(PDO $pdo, array $config, string $method, string $path): bool
{
    field_returns_ensure_schema($pdo);

    if ($method === 'POST' && $path === '/api/field-returns') {
        field_returns_handle_create($pdo, $config);

        return true;
    }

    if ($method === 'GET' && $path === '/api/field-returns/pending') {
        field_returns_handle_list_pending($pdo, $config);

        return true;
    }

    if ($method === 'GET' && $path === '/api/field-returns/list') {
        field_returns_handle_list($pdo, $config);

        return true;
    }

    if ($method === 'POST' && $path === '/api/field-returns/review') {
        field_returns_handle_review($pdo, $config, '', 'from_body');

        return true;
    }

    if ($method === 'POST' && preg_match('#^/api/field-returns/([0-9a-fA-F-]{36})/approve$#', $path, $m)) {
        field_returns_handle_review($pdo, $config, $m[1], 'approved');

        return true;
    }

    if ($method === 'POST' && preg_match('#^/api/field-returns/([0-9a-fA-F-]{36})/reject$#', $path, $m)) {
        field_returns_handle_review($pdo, $config, $m[1], 'rejected');

        return true;
    }

    return false;
}
