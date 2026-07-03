<?php
declare(strict_types=1);

/**
 * مزامنة سحابية لحسابات فريق العمل (موظفين/موزّعين) — منفصلة عن signup_requests.
 * مسارات جديدة فقط؛ لا تغيّر تفعيل/قسائم المشتركين الحاليين.
 */

require_once __DIR__ . '/field_orders.php';
require_once __DIR__ . '/distributor_license.php';

function team_users_list_has_cloud_distributor_role(array $users): bool
{
    foreach ($users as $u) {
        if (strtolower(trim((string) ($u['role'] ?? ''))) !== 'distributor') {
            continue;
        }
        $cloud = $u['distributorCloudEnabled'] ?? $u['distributor_cloud_enabled'] ?? false;
        if ($cloud === true || $cloud === 1 || $cloud === '1') {
            return true;
        }
    }

    return false;
}

function team_users_list_has_distributor_role(array $users): bool
{
    foreach ($users as $u) {
        if (strtolower(trim((string) ($u['role'] ?? ''))) === 'distributor') {
            return true;
        }
    }

    return false;
}

function team_users_ensure_schema(PDO $pdo): void
{
    field_orders_ensure_schema($pdo);
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS team_users_meta (
            organization_id TEXT PRIMARY KEY,
            version TEXT NOT NULL,
            user_count INTEGER NOT NULL DEFAULT 0,
            published_by_email TEXT,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS team_users (
            id TEXT PRIMARY KEY,
            organization_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            username TEXT NOT NULL,
            email TEXT NOT NULL DEFAULT '',
            full_name TEXT NOT NULL,
            role TEXT NOT NULL,
            branch_id TEXT NOT NULL DEFAULT '',
            password_hash TEXT NOT NULL,
            dial_code TEXT NOT NULL DEFAULT '+970',
            phone TEXT NOT NULL DEFAULT '',
            account_status TEXT NOT NULL DEFAULT 'active',
            deleted INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT NOT NULL
        );
        CREATE UNIQUE INDEX IF NOT EXISTS uq_team_users_org_user
            ON team_users(organization_id, user_id);
        CREATE INDEX IF NOT EXISTS idx_team_users_org_active
            ON team_users(organization_id, deleted, updated_at);
    ");
    $cols = $pdo->query('PRAGMA table_info(team_users)')->fetchAll(PDO::FETCH_ASSOC);
    $names = [];
    foreach ($cols as $c) {
        $names[(string) ($c['name'] ?? '')] = true;
    }
    if (!isset($names['distributor_cloud_enabled'])) {
        $pdo->exec('ALTER TABLE team_users ADD COLUMN distributor_cloud_enabled INTEGER NOT NULL DEFAULT 0');
    }
    if (!isset($names['subscription_email'])) {
        $pdo->exec('ALTER TABLE team_users ADD COLUMN subscription_email TEXT NOT NULL DEFAULT \'\'');
    }
}

function team_users_bump_meta(PDO $pdo, string $organizationId, string $email): string
{
    $now = activation_now_iso();
    $version = $now;
    $cntSt = $pdo->prepare(
        'SELECT COUNT(*) AS n FROM team_users
         WHERE trim(organization_id) = trim(?) AND deleted = 0',
    );
    $cntSt->execute([$organizationId]);
    $count = (int) ($cntSt->fetch(PDO::FETCH_ASSOC)['n'] ?? 0);
    $pdo->prepare(
        'INSERT INTO team_users_meta (
            organization_id, version, user_count, published_by_email, updated_at
        ) VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(organization_id) DO UPDATE SET
            version = excluded.version,
            user_count = excluded.user_count,
            published_by_email = excluded.published_by_email,
            updated_at = excluded.updated_at',
    )->execute([$organizationId, $version, $count, $email, $now]);

    return $version;
}

/** @return array<string,mixed>|null */
function team_users_fetch_meta(PDO $pdo, string $organizationId): ?array
{
    $st = $pdo->prepare(
        'SELECT * FROM team_users_meta WHERE trim(organization_id) = trim(?) LIMIT 1',
    );
    $st->execute([$organizationId]);
    $row = $st->fetch(PDO::FETCH_ASSOC);

    return $row === false ? null : $row;
}

/** @return list<array<string,mixed>> */
function team_users_fetch_all(
    PDO $pdo,
    string $organizationId,
    bool $includeDeleted = true,
    ?string $subscriptionEmail = null,
): array {
    $sql = 'SELECT * FROM team_users WHERE trim(organization_id) = trim(?)';
    $params = [$organizationId];
    if ($subscriptionEmail !== null && strpos($subscriptionEmail, '@') !== false) {
        $email = strtolower(trim($subscriptionEmail));
        $meta = team_users_fetch_meta($pdo, $organizationId);
        $publishedBy = strtolower(trim((string) ($meta['published_by_email'] ?? '')));
        $sql .= ' AND (
            lower(trim(COALESCE(subscription_email, \'\'))) = ?
            OR (
                trim(COALESCE(subscription_email, \'\')) = \'\'
                AND ? <> \'\'
                AND ? = ?
            )
        )';
        $params[] = $email;
        $params[] = $publishedBy;
        $params[] = $publishedBy;
        $params[] = $email;
    }
    if (!$includeDeleted) {
        $sql .= ' AND deleted = 0';
    }
    $sql .= ' ORDER BY updated_at ASC';
    $st = $pdo->prepare($sql);
    $st->execute($params);
    $items = [];
    foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $items[] = team_users_row_to_public($row);
    }

    return $items;
}

/** @param array<string,mixed> $row */
function team_users_row_to_public(array $row): array
{
    return [
        'userId' => (string) $row['user_id'],
        'username' => (string) $row['username'],
        'email' => (string) ($row['email'] ?? ''),
        'fullName' => (string) $row['full_name'],
        'role' => (string) $row['role'],
        'branchId' => (string) ($row['branch_id'] ?? ''),
        'passwordHash' => (string) $row['password_hash'],
        'dialCode' => (string) ($row['dial_code'] ?? '+970'),
        'phone' => (string) ($row['phone'] ?? ''),
        'accountStatus' => (string) ($row['account_status'] ?? 'active'),
        'distributorCloudEnabled' => ((int) ($row['distributor_cloud_enabled'] ?? 0)) === 1,
        'subscriptionEmail' => (string) ($row['subscription_email'] ?? ''),
        'deleted' => ((int) ($row['deleted'] ?? 0)) !== 0,
        'updatedAt' => (string) ($row['updated_at'] ?? ''),
    ];
}

/** @param array<string,mixed> $raw */
function team_users_parse_user(array $raw): ?array
{
    $userId = trim((string) ($raw['userId'] ?? $raw['user_id'] ?? $raw['id'] ?? ''));
    $username = trim((string) ($raw['username'] ?? ''));
    $fullName = trim((string) ($raw['fullName'] ?? $raw['full_name'] ?? ''));
    $role = strtolower(trim((string) ($raw['role'] ?? '')));
    $passwordHash = trim((string) ($raw['passwordHash'] ?? $raw['password_hash'] ?? ''));
    if ($userId === '' || $username === '' || $fullName === '' || $role === '') {
        return null;
    }
    if ($role === 'guest' || $role === 'owner') {
        return null;
    }
    if ($passwordHash === '' || !str_starts_with($passwordHash, '$2')) {
        return null;
    }
    $email = strtolower(trim((string) ($raw['email'] ?? '')));
    if ($email === '' && str_contains(strtolower($username), '@')) {
        $email = strtolower(trim($username));
    }
    $cloudRaw = $raw['distributorCloudEnabled'] ?? $raw['distributor_cloud_enabled'] ?? 0;
    $cloudEnabled = $cloudRaw === true || $cloudRaw === 1 || $cloudRaw === '1';

    return [
        'user_id' => $userId,
        'username' => $username,
        'email' => $email,
        'full_name' => $fullName,
        'role' => $role,
        'branch_id' => trim((string) ($raw['branchId'] ?? $raw['branch_id'] ?? '')),
        'password_hash' => $passwordHash,
        'dial_code' => trim((string) ($raw['dialCode'] ?? $raw['dial_code'] ?? '+970')) ?: '+970',
        'phone' => trim((string) ($raw['phone'] ?? '')),
        'account_status' => trim((string) ($raw['accountStatus'] ?? $raw['account_status'] ?? 'active')) ?: 'active',
        'distributor_cloud_enabled' => $cloudEnabled ? 1 : 0,
    ];
}

/** @param list<array<string,mixed>> $rawUsers */
function team_users_parse_users(array $rawUsers): array
{
    $items = [];
    foreach ($rawUsers as $raw) {
        if (!is_array($raw)) {
            continue;
        }
        $parsed = team_users_parse_user($raw);
        if ($parsed !== null) {
            $items[] = $parsed;
        }
    }

    return $items;
}

function team_users_upsert_row(
    PDO $pdo,
    string $organizationId,
    array $user,
    string $now,
    string $subscriptionEmail = '',
): void {
    $subscriptionEmail = strtolower(trim($subscriptionEmail));
    $existing = $pdo->prepare(
        'SELECT id FROM team_users
         WHERE trim(organization_id) = trim(?) AND trim(user_id) = trim(?)
         LIMIT 1',
    );
    $existing->execute([$organizationId, $user['user_id']]);
    $row = $existing->fetch(PDO::FETCH_ASSOC);
    if ($row === false) {
        $pdo->prepare(
            'INSERT INTO team_users (
                id, organization_id, user_id, username, email, full_name, role, branch_id,
                password_hash, dial_code, phone, account_status, distributor_cloud_enabled,
                subscription_email, deleted, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)',
        )->execute([
            activation_uuid(),
            $organizationId,
            $user['user_id'],
            $user['username'],
            $user['email'],
            $user['full_name'],
            $user['role'],
            $user['branch_id'],
            $user['password_hash'],
            $user['dial_code'],
            $user['phone'],
            $user['account_status'],
            (int) ($user['distributor_cloud_enabled'] ?? 0),
            $subscriptionEmail,
            $now,
        ]);

        return;
    }
    $pdo->prepare(
        'UPDATE team_users SET
            username = ?,
            email = ?,
            full_name = ?,
            role = ?,
            branch_id = ?,
            password_hash = ?,
            dial_code = ?,
            phone = ?,
            account_status = ?,
            distributor_cloud_enabled = ?,
            subscription_email = CASE
                WHEN trim(?) <> \'\' THEN ?
                ELSE subscription_email
            END,
            deleted = 0,
            updated_at = ?
         WHERE id = ?',
    )->execute([
        $user['username'],
        $user['email'],
        $user['full_name'],
        $user['role'],
        $user['branch_id'],
        $user['password_hash'],
        $user['dial_code'],
        $user['phone'],
        $user['account_status'],
        (int) ($user['distributor_cloud_enabled'] ?? 0),
        $subscriptionEmail,
        $subscriptionEmail,
        $now,
        (string) $row['id'],
    ]);
}

function team_users_handle_publish(PDO $pdo, array $config): void
{
    $body = activation_json_body();
    $ctx = field_orders_require_org_context($pdo, $config, $body);
    $organizationId = $ctx['organization_id'];

    $rawUsers = $body['users'] ?? [];
    if (!is_array($rawUsers)) {
        activation_json(400, ['error' => 'validation']);
    }
    $users = team_users_parse_users($rawUsers);
    if (count($rawUsers) > 0 && count($users) === 0) {
        activation_json(400, ['error' => 'validation']);
    }
    if (count($users) > 500) {
        activation_json(400, ['error' => 'too_many_users']);
    }
    if (team_users_list_has_cloud_distributor_role($users)) {
        distributor_license_require_cloud($pdo, $organizationId);
        distributor_license_assert_distributor_seats($pdo, $organizationId, $users);
    }

    $now = activation_now_iso();
    $incomingIds = array_map(static fn (array $u): string => $u['user_id'], $users);

    try {
        $pdo->beginTransaction();
        if (count($incomingIds) === 0) {
            $pdo->prepare(
                'UPDATE team_users SET deleted = 1, updated_at = ?
                 WHERE trim(organization_id) = trim(?) AND deleted = 0',
            )->execute([$now, $organizationId]);
        } else {
            $placeholders = implode(',', array_fill(0, count($incomingIds), '?'));
            $mark = $pdo->prepare(
                "UPDATE team_users SET deleted = 1, updated_at = ?
                 WHERE trim(organization_id) = trim(?)
                   AND deleted = 0
                   AND trim(user_id) NOT IN ($placeholders)",
            );
            $mark->execute(array_merge([$now, $organizationId], $incomingIds));
        }
        foreach ($users as $user) {
            team_users_upsert_row($pdo, $organizationId, $user, $now, $ctx['email']);
        }
        $version = team_users_bump_meta($pdo, $organizationId, $ctx['email']);
        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        error_log('[team_users] publish: ' . $e->getMessage());
        activation_json(500, ['error' => 'server_error']);
    }

    activation_json(200, [
        'ok' => true,
        'version' => $version,
        'userCount' => count($users),
        'publishedAt' => $now,
    ]);
}

function team_users_handle_upsert(PDO $pdo, array $config): void
{
    $body = activation_json_body();
    $ctx = field_orders_require_org_context($pdo, $config, $body);
    $organizationId = $ctx['organization_id'];
    $rawUser = $body['user'] ?? null;
    if (!is_array($rawUser)) {
        activation_json(400, ['error' => 'validation']);
    }
    $user = team_users_parse_user($rawUser);
    if ($user === null) {
        activation_json(400, ['error' => 'validation']);
    }
    distributor_license_assert_upsert_distributor($pdo, $organizationId, $user);

    $now = activation_now_iso();
    try {
        $pdo->beginTransaction();
        team_users_upsert_row($pdo, $organizationId, $user, $now, $ctx['email']);
        $version = team_users_bump_meta($pdo, $organizationId, $ctx['email']);
        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        error_log('[team_users] upsert: ' . $e->getMessage());
        activation_json(500, ['error' => 'server_error']);
    }

    activation_json(200, [
        'ok' => true,
        'version' => $version,
        'userId' => $user['user_id'],
        'updatedAt' => $now,
    ]);
}

function team_users_handle_delete(PDO $pdo, array $config): void
{
    $body = activation_json_body();
    $ctx = field_orders_require_org_context($pdo, $config, $body);
    $organizationId = $ctx['organization_id'];
    $userId = trim((string) ($body['userId'] ?? $body['user_id'] ?? ''));
    if ($userId === '') {
        activation_json(400, ['error' => 'validation']);
    }

    $now = activation_now_iso();
    try {
        $pdo->beginTransaction();
        $pdo->prepare(
            'UPDATE team_users SET deleted = 1, updated_at = ?
             WHERE trim(organization_id) = trim(?) AND trim(user_id) = trim(?)',
        )->execute([$now, $organizationId, $userId]);
        $version = team_users_bump_meta($pdo, $organizationId, $ctx['email']);
        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        error_log('[team_users] delete: ' . $e->getMessage());
        activation_json(500, ['error' => 'server_error']);
    }

    activation_json(200, [
        'ok' => true,
        'version' => $version,
        'userId' => $userId,
        'deletedAt' => $now,
    ]);
}

function team_users_handle_get(PDO $pdo, array $config): void
{
    $ctx = field_orders_require_org_context($pdo, $config, $_GET);
    $organizationId = $ctx['organization_id'];
    $sinceVersion = trim((string) ($_GET['sinceVersion'] ?? $_GET['since_version'] ?? ''));

    $meta = team_users_fetch_meta($pdo, $organizationId);
    if ($meta === null) {
        activation_json(200, [
            'ok' => true,
            'version' => null,
            'userCount' => 0,
            'users' => [],
        ]);
    }

    $version = (string) $meta['version'];
    if ($sinceVersion !== '' && $sinceVersion === $version) {
        activation_json(200, [
            'ok' => true,
            'unchanged' => true,
            'version' => $version,
            'userCount' => (int) ($meta['user_count'] ?? 0),
            'publishedAt' => (string) ($meta['updated_at'] ?? ''),
        ]);
    }

    $users = team_users_fetch_all($pdo, $organizationId, true, $ctx['email']);
    activation_json(200, [
        'ok' => true,
        'unchanged' => false,
        'version' => $version,
        'userCount' => (int) ($meta['user_count'] ?? 0),
        'publishedAt' => (string) ($meta['updated_at'] ?? ''),
        'publishedByEmail' => (string) ($meta['published_by_email'] ?? ''),
        'users' => $users,
    ]);
}

function team_users_dispatch(PDO $pdo, array $config, string $method, string $path): bool
{
    team_users_ensure_schema($pdo);

    if ($method === 'POST' && $path === '/api/team-users/publish') {
        team_users_handle_publish($pdo, $config);

        return true;
    }

    if ($method === 'POST' && $path === '/api/team-users/upsert') {
        team_users_handle_upsert($pdo, $config);

        return true;
    }

    if ($method === 'POST' && $path === '/api/team-users/delete') {
        team_users_handle_delete($pdo, $config);

        return true;
    }

    if ($method === 'GET' && $path === '/api/team-users') {
        team_users_handle_get($pdo, $config);

        return true;
    }

    return false;
}
