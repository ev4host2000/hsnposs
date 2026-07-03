<?php
declare(strict_types=1);

/**
 * ترخيص سحابة الموزّعين — منفصل عن قسيمة POS (1 حاسوب + 1 جوال).
 * يُخزَّن على license_snapshots للمنشأة.
 */

function distributor_license_ensure_schema(PDO $pdo): void
{
    $cols = $pdo->query('PRAGMA table_info(license_snapshots)')->fetchAll(PDO::FETCH_ASSOC);
    $names = [];
    foreach ($cols as $c) {
        $names[(string) ($c['name'] ?? '')] = true;
    }
    if (!isset($names['distributor_cloud_until'])) {
        $pdo->exec('ALTER TABLE license_snapshots ADD COLUMN distributor_cloud_until TEXT');
    }
    if (!isset($names['max_distributor_seats'])) {
        $pdo->exec('ALTER TABLE license_snapshots ADD COLUMN max_distributor_seats INTEGER');
    }
}

/** @return array<string,mixed>|null */
function distributor_license_snapshot_for_org(PDO $pdo, string $organizationId): ?array
{
    distributor_license_ensure_schema($pdo);
    $organizationId = trim($organizationId);
    if ($organizationId === '') {
        return null;
    }
    $st = $pdo->prepare(
        'SELECT * FROM license_snapshots
         WHERE trim(organization_id) = trim(?)
         ORDER BY updated_at DESC
         LIMIT 1',
    );
    $st->execute([$organizationId]);
    $row = $st->fetch(PDO::FETCH_ASSOC);

    return $row === false ? null : $row;
}

function distributor_license_cloud_until_iso(?array $snapshot): ?string
{
    if ($snapshot === null) {
        return null;
    }
    $raw = isset($snapshot['distributor_cloud_until'])
        ? trim((string) $snapshot['distributor_cloud_until'])
        : '';

    return $raw !== '' ? $raw : null;
}

function distributor_license_is_active_for_org(PDO $pdo, string $organizationId): bool
{
    $snap = distributor_license_snapshot_for_org($pdo, $organizationId);
    $until = distributor_license_cloud_until_iso($snap);
    if ($until === null) {
        return false;
    }
    $ts = strtotime($until);

    return $ts !== false && $ts >= time();
}

function distributor_license_max_seats(?array $snapshot): ?int
{
    if ($snapshot === null || !array_key_exists('max_distributor_seats', $snapshot)) {
        return null;
    }
    $v = $snapshot['max_distributor_seats'];
    if ($v === null || $v === '') {
        return null;
    }

    return max(0, (int) $v);
}

function distributor_license_count_distributor_seats(PDO $pdo, string $organizationId): int
{
    $organizationId = trim($organizationId);
    if ($organizationId === '') {
        return 0;
    }
    try {
        $st = $pdo->prepare(
            "SELECT COUNT(*) AS n FROM team_users
             WHERE trim(organization_id) = trim(?)
               AND deleted = 0
               AND lower(trim(role)) = 'distributor'
               AND COALESCE(distributor_cloud_enabled, 0) = 1",
        );
        $st->execute([$organizationId]);

        return (int) ($st->fetch(PDO::FETCH_ASSOC)['n'] ?? 0);
    } catch (Throwable $e) {
        return 0;
    }
}

function distributor_license_require_cloud(PDO $pdo, string $organizationId): void
{
    if (!distributor_license_is_active_for_org($pdo, $organizationId)) {
        activation_json(403, [
            'error' => 'distributor_cloud_required',
            'message' => 'Distributor cloud subscription is required.',
        ]);
    }
}

function distributor_license_trial_product_limit(): int
{
    return 5;
}

function distributor_license_trial_expense_limit(): int
{
    return 3;
}

function distributor_license_enforce_trial_product_count(
    PDO $pdo,
    string $organizationId,
    int $count,
): void {
    if (distributor_license_is_active_for_org($pdo, $organizationId)) {
        return;
    }
    if ($count > distributor_license_trial_product_limit()) {
        activation_json(403, [
            'error' => 'distributor_trial_product_limit',
            'limit' => distributor_license_trial_product_limit(),
        ]);
    }
}

function distributor_license_enforce_trial_expense_create(
    PDO $pdo,
    string $organizationId,
): void {
    if (distributor_license_is_active_for_org($pdo, $organizationId)) {
        return;
    }
    $st = $pdo->prepare(
        'SELECT COUNT(*) FROM field_expenses WHERE trim(organization_id) = trim(?)',
    );
    $st->execute([$organizationId]);
    $n = (int) ($st->fetchColumn() ?: 0);
    if ($n >= distributor_license_trial_expense_limit()) {
        activation_json(403, [
            'error' => 'distributor_trial_expense_limit',
            'limit' => distributor_license_trial_expense_limit(),
        ]);
    }
}

/** @param array<string,mixed> $user parsed team_users row */
function distributor_license_assert_upsert_distributor(
    PDO $pdo,
    string $organizationId,
    array $user,
): void {
    $role = strtolower(trim((string) ($user['role'] ?? '')));
    if ($role !== 'distributor') {
        return;
    }
    $cloud = (int) ($user['distributor_cloud_enabled'] ?? $user['distributorCloudEnabled'] ?? 0);
    if ($cloud !== 1) {
        return;
    }
    distributor_license_require_cloud($pdo, $organizationId);
    $snap = distributor_license_snapshot_for_org($pdo, $organizationId);
    $max = distributor_license_max_seats($snap);
    if ($max === null) {
        return;
    }
    $userId = trim((string) ($user['user_id'] ?? ''));
    if ($userId !== '') {
        $st = $pdo->prepare(
            "SELECT 1 FROM team_users
             WHERE trim(organization_id) = trim(?)
               AND trim(user_id) = trim(?)
               AND deleted = 0
               AND lower(trim(role)) = 'distributor'
               AND COALESCE(distributor_cloud_enabled, 0) = 1
             LIMIT 1",
        );
        $st->execute([$organizationId, $userId]);
        if ($st->fetchColumn()) {
            return;
        }
    }
    $used = distributor_license_count_distributor_seats($pdo, $organizationId);
    if ($used >= $max) {
        activation_json(403, [
            'error' => 'distributor_seats_limit',
            'max' => $max,
            'used' => $used,
        ]);
    }
}

/** @param list<array<string,mixed>> $users parsed team_users */
function distributor_license_assert_distributor_seats(
    PDO $pdo,
    string $organizationId,
    array $users,
): void {
    $snap = distributor_license_snapshot_for_org($pdo, $organizationId);
    $max = distributor_license_max_seats($snap);
    if ($max === null) {
        return;
    }
    $incoming = 0;
    foreach ($users as $u) {
        if (strtolower(trim((string) ($u['role'] ?? ''))) !== 'distributor') {
            continue;
        }
        $cloud = (int) ($u['distributor_cloud_enabled'] ?? $u['distributorCloudEnabled'] ?? 0);
        if ($cloud === 1) {
            $incoming++;
        }
    }
    if ($incoming <= $max) {
        return;
    }
    activation_json(403, [
        'error' => 'distributor_seats_limit',
        'max' => $max,
        'requested' => $incoming,
    ]);
}

/** @return array<string,mixed> */
function distributor_license_public_fields(PDO $pdo, string $organizationId): array
{
    $snap = distributor_license_snapshot_for_org($pdo, $organizationId);
    $until = distributor_license_cloud_until_iso($snap);
    $max = distributor_license_max_seats($snap);
    $used = distributor_license_count_distributor_seats($pdo, $organizationId);
    $active = distributor_license_is_active_for_org($pdo, $organizationId);

    return [
        'distributorCloudUntil' => $until,
        'maxDistributorSeats' => $max,
        'usedDistributorSeats' => $used,
        'distributorCloudActive' => $active,
    ];
}

/** @return array{ok:bool, error?:string, distributorCloudUntil?:string|null, maxDistributorSeats?:int|null} */
function distributor_license_apply_admin_action(
    PDO $pdo,
    array $admin,
    string $organizationId,
    string $email,
    string $action,
    array $body,
): array {
    distributor_license_ensure_schema($pdo);
    $organizationId = trim($organizationId);
    $email = strtolower(trim($email));
    if ($organizationId === '' || strpos($email, '@') === false) {
        return ['ok' => false, 'error' => 'validation'];
    }
    $now = activation_now_iso();

    $st = $pdo->prepare(
        'SELECT 1 FROM license_snapshots WHERE organization_id = ? AND email_normalized = ?',
    );
    $st->execute([$organizationId, $email]);
    if (!$st->fetchColumn()) {
        $ins = $pdo->prepare(
            'INSERT INTO license_snapshots (
                organization_id, email_normalized, trial_end_at, subscription_annual_until,
                legacy_activated, updated_at, admin_valid_until, access_suspended,
                distributor_cloud_until, max_distributor_seats
            ) VALUES (?, ?, NULL, NULL, 0, ?, NULL, 0, NULL, NULL)',
        );
        $ins->execute([$organizationId, $email, $now]);
    }

    if ($action === 'extend_distributor_cloud') {
        $days = max(1, min(3660, (int) ($body['days'] ?? 365)));
        $snap = distributor_license_snapshot_for_org($pdo, $organizationId);
        $base = distributor_license_cloud_until_iso($snap);
        $from = $base !== null && strtotime($base) > time() ? strtotime($base) : time();
        $until = gmdate('c', $from + ($days * 86400));
        $pdo->prepare(
            'UPDATE license_snapshots
             SET distributor_cloud_until = ?, updated_at = ?
             WHERE organization_id = ? AND email_normalized = ?',
        )->execute([$until, $now, $organizationId, $email]);
        activation_log_subscriber_event($pdo, $organizationId, $email, $admin, 'distributor_cloud_extended', [
            'days' => $days,
            'until' => $until,
        ]);

        return ['ok' => true, 'distributorCloudUntil' => $until];
    }

    if ($action === 'set_distributor_cloud_until') {
        $untilRaw = trim((string) ($body['distributorCloudUntil'] ?? ''));
        $until = $untilRaw !== '' ? $untilRaw : null;
        $pdo->prepare(
            'UPDATE license_snapshots
             SET distributor_cloud_until = ?, updated_at = ?
             WHERE organization_id = ? AND email_normalized = ?',
        )->execute([$until, $now, $organizationId, $email]);
        activation_log_subscriber_event($pdo, $organizationId, $email, $admin, 'distributor_cloud_set', [
            'until' => $until,
        ]);

        return ['ok' => true, 'distributorCloudUntil' => $until];
    }

    if ($action === 'set_distributor_seats') {
        $seatsRaw = $body['maxDistributorSeats'] ?? null;
        $seats = null;
        if ($seatsRaw !== null && $seatsRaw !== '') {
            $seats = max(0, min(9999, (int) $seatsRaw));
        }
        $pdo->prepare(
            'UPDATE license_snapshots
             SET max_distributor_seats = ?, updated_at = ?
             WHERE organization_id = ? AND email_normalized = ?',
        )->execute([$seats, $now, $organizationId, $email]);
        activation_log_subscriber_event($pdo, $organizationId, $email, $admin, 'distributor_seats_set', [
            'max' => $seats,
        ]);

        return ['ok' => true, 'maxDistributorSeats' => $seats];
    }

    if ($action === 'clear_distributor_cloud') {
        $pdo->prepare(
            'UPDATE license_snapshots
             SET distributor_cloud_until = NULL, updated_at = ?
             WHERE organization_id = ? AND email_normalized = ?',
        )->execute([$now, $organizationId, $email]);
        activation_log_subscriber_event($pdo, $organizationId, $email, $admin, 'distributor_cloud_cleared', []);

        return ['ok' => true, 'distributorCloudUntil' => null];
    }

    return ['ok' => false, 'error' => 'unknown_action'];
}

/** @return array<string,mixed> */
function distributor_license_voucher_cloud_fields(array $v): array
{
    $untilRaw = isset($v['distributor_cloud_until'])
        ? trim((string) $v['distributor_cloud_until'])
        : '';
    $until = $untilRaw !== '' ? $untilRaw : null;
    $daysRaw = $v['distributor_cloud_days'] ?? null;
    $days = ($daysRaw === null || $daysRaw === '') ? 0 : max(0, (int) $daysRaw);
    $seats = distributor_license_max_seats($v);
    $active = $until !== null
        && ($ts = strtotime($until)) !== false
        && $ts >= time();

    return [
        'distributorCloudDays' => $days,
        'distributorCloudUntil' => $until,
        'maxDistributorSeats' => $seats,
        'distributorCloudActive' => $active,
        'distributorCloudEnabled' => $days > 0 || $until !== null,
    ];
}

/** @return array<string,mixed>|null */
function distributor_license_voucher_row(PDO $pdo, string $code): ?array
{
    $code = trim($code);
    if ($code === '') {
        return null;
    }
    $st = $pdo->prepare('SELECT * FROM vouchers WHERE code = ? LIMIT 1');
    $st->execute([$code]);
    $row = $st->fetch(PDO::FETCH_ASSOC);

    return $row === false ? null : $row;
}

function distributor_license_sync_voucher_to_org(
    PDO $pdo,
    array $admin,
    string $voucherCode,
    string $event = 'distributor_cloud_voucher_sync',
): void {
    distributor_license_ensure_schema($pdo);
    $v = distributor_license_voucher_row($pdo, $voucherCode);
    if ($v === null) {
        return;
    }
    $email = strtolower(trim((string) ($v['redeemed_by_email'] ?? '')));
    $organizationId = trim((string) ($v['redeemed_by_organization_id'] ?? ''));
    if ($email === '' || $organizationId === '' || strpos($email, '@') === false) {
        return;
    }
    $cloud = distributor_license_voucher_cloud_fields($v);
    $until = $cloud['distributorCloudUntil'];
    $seats = $cloud['maxDistributorSeats'];
    $now = activation_now_iso();

    $st = $pdo->prepare(
        'SELECT 1 FROM license_snapshots WHERE organization_id = ? AND email_normalized = ?',
    );
    $st->execute([$organizationId, $email]);
    if (!$st->fetchColumn()) {
        $ins = $pdo->prepare(
            'INSERT INTO license_snapshots (
                organization_id, email_normalized, trial_end_at, subscription_annual_until,
                legacy_activated, updated_at, admin_valid_until, access_suspended,
                distributor_cloud_until, max_distributor_seats
            ) VALUES (?, ?, NULL, NULL, 0, ?, NULL, 0, ?, ?)',
        );
        $ins->execute([$organizationId, $email, $now, $until, $seats]);
    } else {
        $pdo->prepare(
            'UPDATE license_snapshots
             SET distributor_cloud_until = ?, max_distributor_seats = ?, updated_at = ?
             WHERE organization_id = ? AND email_normalized = ?',
        )->execute([$until, $seats, $now, $organizationId, $email]);
    }
    activation_log_subscriber_event($pdo, $organizationId, $email, $admin, $event, [
        'voucherCode' => $voucherCode,
        'until' => $until,
        'maxSeats' => $seats,
    ]);
}

function distributor_license_apply_voucher_cloud_on_redeem(PDO $pdo, string $voucherCode): void
{
    $v = distributor_license_voucher_row($pdo, $voucherCode);
    if ($v === null) {
        return;
    }
    $cloud = distributor_license_voucher_cloud_fields($v);
    if (empty($cloud['distributorCloudEnabled'])) {
        return;
    }
    if ($cloud['distributorCloudUntil'] === null && (int) $cloud['distributorCloudDays'] > 0) {
        $days = max(1, min(3660, (int) $cloud['distributorCloudDays']));
        $until = gmdate('c', time() + ($days * 86400));
        $now = activation_now_iso();
        $pdo->prepare(
            'UPDATE vouchers SET distributor_cloud_until = ? WHERE code = ?',
        )->execute([$until, $voucherCode]);
    }
    distributor_license_sync_voucher_to_org($pdo, [
        'email' => 'system',
        'admin_role' => 'system',
    ], $voucherCode, 'distributor_cloud_voucher_redeemed');
}

/** @return array{ok:bool, error?:string, distributorCloudUntil?:string|null, maxDistributorSeats?:int|null, usedDistributorSeats?:int} */
function distributor_license_apply_voucher_admin_action(
    PDO $pdo,
    array $admin,
    string $voucherCode,
    string $action,
    array $body,
): array {
    distributor_license_ensure_schema($pdo);
    $voucherCode = trim($voucherCode);
    if ($voucherCode === '') {
        return ['ok' => false, 'error' => 'validation'];
    }
    $v = distributor_license_voucher_row($pdo, $voucherCode);
    if ($v === null) {
        return ['ok' => false, 'error' => 'voucher_not_found'];
    }
    $now = activation_now_iso();

    if ($action === 'extend_distributor_cloud') {
        $days = max(1, min(3660, (int) ($body['days'] ?? 365)));
        $cloud = distributor_license_voucher_cloud_fields($v);
        $base = $cloud['distributorCloudUntil'];
        $from = $base !== null && ($ts = strtotime($base)) !== false && $ts > time()
            ? $ts
            : time();
        $until = gmdate('c', $from + ($days * 86400));
        $pdo->prepare(
            'UPDATE vouchers SET distributor_cloud_until = ?, distributor_cloud_days = COALESCE(distributor_cloud_days, ?)
             WHERE code = ?',
        )->execute([$until, $days, $voucherCode]);
        distributor_license_sync_voucher_to_org($pdo, $admin, $voucherCode, 'distributor_cloud_voucher_extended');
        $orgId = trim((string) ($v['redeemed_by_organization_id'] ?? ''));

        return [
            'ok' => true,
            'distributorCloudUntil' => $until,
            'usedDistributorSeats' => $orgId !== ''
                ? distributor_license_count_distributor_seats($pdo, $orgId)
                : 0,
        ];
    }

    if ($action === 'set_distributor_cloud_until') {
        $untilRaw = trim((string) ($body['distributorCloudUntil'] ?? ''));
        $until = $untilRaw !== '' ? $untilRaw : null;
        $pdo->prepare(
            'UPDATE vouchers SET distributor_cloud_until = ? WHERE code = ?',
        )->execute([$until, $voucherCode]);
        distributor_license_sync_voucher_to_org($pdo, $admin, $voucherCode, 'distributor_cloud_voucher_set');
        $orgId = trim((string) ($v['redeemed_by_organization_id'] ?? ''));

        return [
            'ok' => true,
            'distributorCloudUntil' => $until,
            'usedDistributorSeats' => $orgId !== ''
                ? distributor_license_count_distributor_seats($pdo, $orgId)
                : 0,
        ];
    }

    if ($action === 'set_distributor_seats') {
        $seatsRaw = $body['maxDistributorSeats'] ?? null;
        $seats = null;
        if ($seatsRaw !== null && $seatsRaw !== '') {
            $seats = max(0, min(9999, (int) $seatsRaw));
        }
        $pdo->prepare(
            'UPDATE vouchers SET max_distributor_seats = ? WHERE code = ?',
        )->execute([$seats, $voucherCode]);
        distributor_license_sync_voucher_to_org($pdo, $admin, $voucherCode, 'distributor_cloud_voucher_seats');
        $orgId = trim((string) ($v['redeemed_by_organization_id'] ?? ''));

        return [
            'ok' => true,
            'maxDistributorSeats' => $seats,
            'usedDistributorSeats' => $orgId !== ''
                ? distributor_license_count_distributor_seats($pdo, $orgId)
                : 0,
        ];
    }

    if ($action === 'clear_distributor_cloud') {
        $pdo->prepare(
            'UPDATE vouchers
             SET distributor_cloud_until = NULL, distributor_cloud_days = NULL, max_distributor_seats = NULL
             WHERE code = ?',
        )->execute([$voucherCode]);
        distributor_license_sync_voucher_to_org($pdo, $admin, $voucherCode, 'distributor_cloud_voucher_cleared');

        return ['ok' => true, 'distributorCloudUntil' => null, 'maxDistributorSeats' => null];
    }

    if ($action === 'enable_distributor_cloud') {
        $days = max(1, min(3660, (int) ($body['days'] ?? 365)));
        $seatsRaw = $body['maxDistributorSeats'] ?? null;
        $seats = null;
        if ($seatsRaw !== null && $seatsRaw !== '') {
            $seats = max(0, min(9999, (int) $seatsRaw));
        }
        $pdo->prepare(
            'UPDATE vouchers SET distributor_cloud_days = ?, max_distributor_seats = ? WHERE code = ?',
        )->execute([$days, $seats, $voucherCode]);
        $v = distributor_license_voucher_row($pdo, $voucherCode) ?? $v;
        $email = strtolower(trim((string) ($v['redeemed_by_email'] ?? '')));
        $orgId = trim((string) ($v['redeemed_by_organization_id'] ?? ''));
        if ($email !== '' && $orgId !== '') {
            distributor_license_apply_voucher_cloud_on_redeem($pdo, $voucherCode);
        }

        return array_merge(['ok' => true], distributor_license_voucher_cloud_fields(
            distributor_license_voucher_row($pdo, $voucherCode) ?? $v,
        ));
    }

    return ['ok' => false, 'error' => 'unknown_action'];
}
