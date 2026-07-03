<?php
declare(strict_types=1);

/**
 * مصروفات الميدان من الموزّع — اعتماد/رفض من الحاسوب ثم تسجيل محلي.
 */

require_once __DIR__ . '/field_orders.php';

/** @return list<string> */
function field_expenses_valid_statuses(): array
{
    return ['pending', 'approved', 'rejected'];
}

function field_expenses_ensure_schema(PDO $pdo): void
{
    field_orders_ensure_schema($pdo);
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS field_expenses (
            id TEXT PRIMARY KEY,
            organization_id TEXT NOT NULL,
            client_expense_id TEXT,
            status TEXT NOT NULL DEFAULT 'pending',
            submitter_email TEXT NOT NULL,
            submitter_name TEXT,
            distributor_user_id TEXT,
            distributor_display_name TEXT,
            installation_id TEXT,
            title TEXT NOT NULL,
            amount REAL NOT NULL,
            notes TEXT,
            payment_type TEXT NOT NULL DEFAULT 'cash',
            expense_date TEXT NOT NULL,
            reject_reason TEXT,
            reviewed_by_email TEXT,
            reviewed_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE UNIQUE INDEX IF NOT EXISTS uq_field_expenses_client
            ON field_expenses(organization_id, client_expense_id)
            WHERE client_expense_id IS NOT NULL AND trim(client_expense_id) <> '';
        CREATE INDEX IF NOT EXISTS idx_field_expenses_org_status_created
            ON field_expenses(organization_id, status, created_at DESC);
    ");
}

/** @return array<string,mixed>|null */
function field_expenses_fetch_row_by_reference(
    PDO $pdo,
    string $expenseId,
    string $clientExpenseId,
    string $organizationId,
): ?array {
    $expenseId = trim($expenseId);
    if ($expenseId !== '') {
        $st = $pdo->prepare('SELECT * FROM field_expenses WHERE id = ? LIMIT 1');
        $st->execute([$expenseId]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if ($row) {
            return $row;
        }
    }
    $clientExpenseId = trim($clientExpenseId);
    $organizationId = trim($organizationId);
    if ($clientExpenseId !== '' && $organizationId !== '') {
        $st = $pdo->prepare(
            'SELECT * FROM field_expenses
             WHERE trim(organization_id) = trim(?) AND client_expense_id = ?
             LIMIT 1',
        );
        $st->execute([$organizationId, $clientExpenseId]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if ($row) {
            return $row;
        }
    }
    if ($clientExpenseId !== '') {
        $st = $pdo->prepare(
            'SELECT * FROM field_expenses WHERE client_expense_id = ? LIMIT 1',
        );
        $st->execute([$clientExpenseId]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if ($row) {
            return $row;
        }
    }

    return null;
}

function field_expenses_can_access(PDO $pdo, array $ctx, array $row): bool
{
    return field_orders_can_access_order($pdo, $ctx, $row);
}

/** @param array<string,mixed> $row */
function field_expenses_row_to_public(array $row): array
{
    return [
        'id' => (string) $row['id'],
        'organizationId' => (string) $row['organization_id'],
        'clientExpenseId' => (string) ($row['client_expense_id'] ?? ''),
        'status' => (string) $row['status'],
        'submitterEmail' => (string) $row['submitter_email'],
        'submitterName' => (string) ($row['submitter_name'] ?? ''),
        'distributorUserId' => (string) ($row['distributor_user_id'] ?? ''),
        'distributorDisplayName' => (string) ($row['distributor_display_name'] ?? ''),
        'installationId' => (string) ($row['installation_id'] ?? ''),
        'title' => (string) $row['title'],
        'amount' => (float) $row['amount'],
        'notes' => (string) ($row['notes'] ?? ''),
        'paymentType' => (string) ($row['payment_type'] ?? 'cash'),
        'expenseDate' => (string) $row['expense_date'],
        'rejectReason' => (string) ($row['reject_reason'] ?? ''),
        'reviewedByEmail' => (string) ($row['reviewed_by_email'] ?? ''),
        'reviewedAt' => (string) ($row['reviewed_at'] ?? ''),
        'createdAt' => (string) $row['created_at'],
        'updatedAt' => (string) $row['updated_at'],
    ];
}

function field_expenses_fetch_public(PDO $pdo, string $expenseId, string $organizationId): ?array
{
    $st = $pdo->prepare(
        'SELECT * FROM field_expenses WHERE id = ? AND trim(organization_id) = trim(?) LIMIT 1',
    );
    $st->execute([$expenseId, $organizationId]);
    $row = $st->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return null;
    }

    return field_expenses_row_to_public($row);
}

function field_expenses_normalize_payment_type(string $raw): string
{
    $v = strtolower(trim($raw));
    if ($v === '') {
        return 'cash';
    }

    return $v;
}

/** @param array<string,mixed> $body */
function field_expenses_handle_create(PDO $pdo, array $config): void
{
    $body = activation_json_body();
    $ctx = field_orders_require_distributor_cloud_context($pdo, $config, $body);

    $organizationId = $ctx['organization_id'];
    distributor_license_enforce_trial_expense_create($pdo, $organizationId);
    $clientExpenseId = trim((string) ($body['clientExpenseId'] ?? $body['client_expense_id'] ?? ''));
    if ($clientExpenseId !== '') {
        $dup = $pdo->prepare(
            'SELECT id FROM field_expenses
             WHERE trim(organization_id) = trim(?) AND client_expense_id = ? LIMIT 1',
        );
        $dup->execute([$organizationId, $clientExpenseId]);
        $existingId = (string) ($dup->fetchColumn() ?: '');
        if ($existingId !== '') {
            $expense = field_expenses_fetch_public($pdo, $existingId, $organizationId);
            activation_json(200, ['ok' => true, 'duplicate' => true, 'expense' => $expense]);
        }
    }

    $title = trim((string) ($body['title'] ?? ''));
    if ($title === '') {
        activation_json(400, ['error' => 'title_required']);
    }
    $amount = (float) ($body['amount'] ?? 0);
    if (!is_finite($amount) || $amount <= 0) {
        activation_json(400, ['error' => 'amount_required']);
    }

    $expenseDate = trim((string) ($body['expenseDate'] ?? $body['expense_date'] ?? ''));
    if ($expenseDate === '') {
        $expenseDate = activation_now_iso();
    }
    $paymentType = field_expenses_normalize_payment_type(
        (string) ($body['paymentType'] ?? $body['payment_type'] ?? 'cash'),
    );

    $now = activation_now_iso();
    $expenseId = activation_uuid();
    $distributorUserId = trim((string) ($body['distributorUserId'] ?? $body['distributor_user_id'] ?? ''));
    $distributorDisplayName = trim((string) (
        $body['distributorDisplayName'] ?? $body['distributor_display_name'] ?? $ctx['full_name']
    ));
    $installationId = trim((string) ($body['installationId'] ?? $body['installation_id'] ?? ''));

    try {
        $ins = $pdo->prepare(
            'INSERT INTO field_expenses (
                id, organization_id, client_expense_id, status,
                submitter_email, submitter_name,
                distributor_user_id, distributor_display_name, installation_id,
                title, amount, notes, payment_type, expense_date,
                reject_reason, reviewed_by_email, reviewed_at,
                created_at, updated_at
            ) VALUES (
                ?, ?, ?, \'pending\',
                ?, ?,
                ?, ?, ?,
                ?, ?, ?, ?, ?,
                NULL, NULL, NULL,
                ?, ?
            )',
        );
        $ins->execute([
            $expenseId,
            $organizationId,
            $clientExpenseId !== '' ? $clientExpenseId : null,
            $ctx['email'],
            $ctx['full_name'],
            $distributorUserId !== '' ? $distributorUserId : null,
            $distributorDisplayName !== '' ? $distributorDisplayName : null,
            $installationId !== '' ? $installationId : null,
            $title,
            $amount,
            trim((string) ($body['notes'] ?? '')) ?: null,
            $paymentType,
            $expenseDate,
            $now,
            $now,
        ]);
    } catch (Throwable $e) {
        error_log('[field_expenses] create: ' . $e->getMessage());
        activation_json(500, ['error' => 'server']);
    }

    $expense = field_expenses_fetch_public($pdo, $expenseId, $organizationId);
    activation_json(201, ['ok' => true, 'expense' => $expense]);
}

function field_expenses_handle_list(PDO $pdo, array $config): void
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

    $sql = 'SELECT * FROM field_expenses WHERE trim(organization_id) = trim(?)';
    $args = [$organizationId];
    if ($installationId !== '') {
        $sql .= ' AND installation_id = ?';
        $args[] = $installationId;
    }
    if (in_array($statusFilter, field_expenses_valid_statuses(), true)) {
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
        $items[] = field_expenses_row_to_public($row);
    }

    activation_json(200, ['ok' => true, 'items' => $items, 'count' => count($items)]);
}

function field_expenses_handle_list_pending(PDO $pdo, array $config): void
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
        'SELECT * FROM field_expenses
         WHERE trim(organization_id) = trim(?) AND status = \'pending\'
         ORDER BY created_at ASC
         LIMIT ?',
    );
    $st->bindValue(1, $organizationId);
    $st->bindValue(2, $limit, PDO::PARAM_INT);
    $st->execute();
    $rows = $st->fetchAll(PDO::FETCH_ASSOC);
    $items = [];
    foreach ($rows as $row) {
        $items[] = field_expenses_row_to_public($row);
    }

    activation_json(200, ['ok' => true, 'items' => $items, 'count' => count($items)]);
}

function field_expenses_handle_get_one(PDO $pdo, array $config, string $expenseId): void
{
    $ctx = field_orders_require_distributor_cloud_context($pdo, $config, $_GET);
    $expense = field_expenses_fetch_public($pdo, $expenseId, $ctx['organization_id']);
    if ($expense === null) {
        activation_json(404, ['error' => 'not_found']);
    }
    activation_json(200, ['ok' => true, 'expense' => $expense]);
}

function field_expenses_handle_review(PDO $pdo, array $config, string $expenseId, string $newStatus): void
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
        $expenseId = trim((string) ($body['expenseId'] ?? $body['id'] ?? ''));
    }
    if (!in_array($newStatus, ['approved', 'rejected'], true)) {
        activation_json(400, ['error' => 'validation']);
    }
    $ctx = field_orders_require_distributor_cloud_context($pdo, $config, array_merge($_GET, $body));
    $organizationId = trim($ctx['organization_id']);
    $clientExpenseId = trim((string) (
        $body['clientExpenseId'] ?? $body['client_expense_id'] ?? $_GET['clientExpenseId'] ?? ''
    ));

    $row = field_expenses_fetch_row_by_reference(
        $pdo,
        $expenseId,
        $clientExpenseId,
        $organizationId,
    );
    if (!$row) {
        activation_json(404, ['error' => 'not_found']);
    }
    if (!field_expenses_can_access($pdo, $ctx, $row)) {
        activation_json(403, ['error' => 'forbidden']);
    }
    $expenseId = (string) $row['id'];
    $current = (string) $row['status'];
    if ($current !== 'pending') {
        activation_json(409, ['error' => 'already_reviewed', 'status' => $current]);
    }

    $rejectReason = trim((string) ($body['rejectReason'] ?? $body['reject_reason'] ?? ''));
    if ($newStatus === 'rejected' && $rejectReason === '') {
        activation_json(400, ['error' => 'reject_reason_required']);
    }

    $now = activation_now_iso();
    try {
        $up = $pdo->prepare(
            'UPDATE field_expenses SET
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
            $expenseId,
        ]);
    } catch (Throwable $e) {
        error_log('[field_expenses] review: ' . $e->getMessage());
        activation_json(500, ['error' => 'server']);
    }

    $updated = field_expenses_fetch_row_by_reference($pdo, $expenseId, '', $organizationId);
    if (!$updated) {
        activation_json(500, ['error' => 'server']);
    }
    $expense = field_expenses_row_to_public($updated);
    activation_json(200, ['ok' => true, 'expense' => $expense]);
}

/** @param array<string,mixed> $body */
function field_expenses_require_pending_for_distributor(
    PDO $pdo,
    array $ctx,
    array $body,
    string $organizationId,
): array {
    $expenseId = trim((string) ($body['expenseId'] ?? $body['id'] ?? ''));
    $clientExpenseId = trim((string) ($body['clientExpenseId'] ?? $body['client_expense_id'] ?? ''));
    $row = field_expenses_fetch_row_by_reference(
        $pdo,
        $expenseId,
        $clientExpenseId,
        $organizationId,
    );
    if (!$row) {
        activation_json(404, ['error' => 'not_found']);
    }
    if (!field_expenses_can_access($pdo, $ctx, $row)) {
        activation_json(403, ['error' => 'forbidden']);
    }
    if ((string) $row['status'] !== 'pending') {
        activation_json(409, ['error' => 'already_reviewed', 'status' => (string) $row['status']]);
    }
    $distId = trim((string) ($row['distributor_user_id'] ?? ''));
    $bodyDist = trim((string) ($body['distributorUserId'] ?? $body['distributor_user_id'] ?? ''));
    if ($bodyDist !== '' && $distId !== '' && $distId !== $bodyDist) {
        activation_json(403, ['error' => 'forbidden']);
    }

    return $row;
}

function field_expenses_handle_cancel(PDO $pdo, array $config): void
{
    $body = activation_json_body();
    $ctx = field_orders_require_distributor_cloud_context($pdo, $config, array_merge($_GET, $body));
    $organizationId = $ctx['organization_id'];
    $row = field_expenses_require_pending_for_distributor($pdo, $ctx, $body, $organizationId);
    $expenseId = (string) $row['id'];
    $pdo->prepare('DELETE FROM field_expenses WHERE id = ?')->execute([$expenseId]);
    activation_json(200, ['ok' => true]);
}

function field_expenses_dispatch(PDO $pdo, array $config, string $method, string $path): bool
{
    field_expenses_ensure_schema($pdo);

    if ($method === 'POST' && $path === '/api/field-expenses') {
        field_expenses_handle_create($pdo, $config);

        return true;
    }

    if ($method === 'GET' && $path === '/api/field-expenses/pending') {
        field_expenses_handle_list_pending($pdo, $config);

        return true;
    }

    if ($method === 'GET' && $path === '/api/field-expenses/list') {
        field_expenses_handle_list($pdo, $config);

        return true;
    }

    if ($method === 'POST' && $path === '/api/field-expenses/review') {
        field_expenses_handle_review($pdo, $config, '', 'from_body');

        return true;
    }

    if ($method === 'POST' && $path === '/api/field-expenses/cancel') {
        field_expenses_handle_cancel($pdo, $config);

        return true;
    }

    if ($method === 'GET' && preg_match('#^/api/field-expenses/([0-9a-fA-F-]{36})$#', $path, $m)) {
        field_expenses_handle_get_one($pdo, $config, $m[1]);

        return true;
    }

    if ($method === 'POST' && preg_match('#^/api/field-expenses/([0-9a-fA-F-]{36})/approve$#', $path, $m)) {
        field_expenses_handle_review($pdo, $config, $m[1], 'approved');

        return true;
    }

    if ($method === 'POST' && preg_match('#^/api/field-expenses/([0-9a-fA-F-]{36})/reject$#', $path, $m)) {
        field_expenses_handle_review($pdo, $config, $m[1], 'rejected');

        return true;
    }

    return false;
}
