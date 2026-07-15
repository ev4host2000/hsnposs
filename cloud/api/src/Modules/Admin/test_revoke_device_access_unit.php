<?php
/**
 * RAP-P0-01 — Calls AdminRepository::revokeDevice and asserts subject_type=user
 * access tokens linked via device_session_id are revoked.
 *
 * Usage:
 *   docker compose … exec -T api php /var/www/html/src/Modules/Admin/test_revoke_device_access_unit.php
 */
declare(strict_types=1);

$root = dirname(__DIR__, 3);
require_once $root . '/vendor/autoload.php';

use MizaCloud\Core\Database\Connection;
use MizaCloud\Modules\Admin\Repositories\AdminRepository;

function fail(string $msg): never
{
    fwrite(STDERR, "FAIL: {$msg}\n");
    exit(1);
}

function pass(string $msg): void
{
    fwrite(STDOUT, "PASS: {$msg}\n");
}

function uuid(): string
{
    $data = random_bytes(16);
    $data[6] = chr((ord($data[6]) & 0x0f) | 0x40);
    $data[8] = chr((ord($data[8]) & 0x3f) | 0x80);

    return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($data), 4));
}

$dbName = getenv('DB_DATABASE') ?: (getenv('DB_NAME') ?: 'mizacloud');
$conn = new Connection([
    'host' => getenv('DB_HOST') ?: 'postgres',
    'port' => (int) (getenv('DB_PORT') ?: 5432),
    'database' => $dbName,
    'username' => getenv('DB_USERNAME') ?: (getenv('DB_USER') ?: 'mizacloud'),
    'password' => getenv('DB_PASSWORD') ?: '',
]);
$pdo = $conn->pdo();
$repo = new AdminRepository($conn);

$companyId = $pdo->query(
    "SELECT id::text FROM companies WHERE status = 'active' ORDER BY created_at NULLS LAST LIMIT 1",
)->fetchColumn();
if (!$companyId) {
    fail('no active company');
}

$st = $pdo->prepare("SELECT id::text FROM branches WHERE company_id = :c AND status = 'active' LIMIT 1");
$st->execute(['c' => $companyId]);
$branchId = $st->fetchColumn();
if (!$branchId) {
    fail('no active branch');
}

$st = $pdo->prepare("SELECT id::text FROM users WHERE company_id = :c AND account_status = 'active' LIMIT 1");
$st->execute(['c' => $companyId]);
$userId = $st->fetchColumn();
if (!$userId) {
    fail('no active user');
}

$deviceId = uuid();
$sessionId = uuid();
$tokenId = uuid();
$refreshId = uuid();
$installId = uuid();
$otherDeviceId = uuid();
$otherSessionId = uuid();
$otherTokenId = uuid();

try {
    $pdo->prepare(
        'INSERT INTO devices (
            id, company_id, installation_id, device_fingerprint, platform,
            device_name, os_name, status, row_version
         ) VALUES (
            :id, :company_id, :installation_id, :fp, \'android\',
            \'RAP-P0-01 Unit\', \'Android\', \'active\', 1
         )',
    )->execute([
        'id' => $deviceId,
        'company_id' => $companyId,
        'installation_id' => $installId,
        'fp' => 'sha256:rap-p0-01-unit-' . $installId,
    ]);

    $pdo->prepare(
        'INSERT INTO device_sessions (
            id, device_id, company_id, branch_id, user_id, session_type, expires_at
         ) VALUES (
            :id, :device_id, :company_id, :branch_id, :user_id, \'user\', now() + interval \'30 days\'
         )',
    )->execute([
        'id' => $sessionId,
        'device_id' => $deviceId,
        'company_id' => $companyId,
        'branch_id' => $branchId,
        'user_id' => $userId,
    ]);

    $pdo->prepare(
        'INSERT INTO api_tokens (
            id, token_hash, subject_type, subject_id, company_id, device_session_id, scopes, expires_at
         ) VALUES (
            :id, :token_hash, \'user\', :subject_id, :company_id, :session_id,
            ARRAY[\'sync:push\']::text[], now() + interval \'15 minutes\'
         )',
    )->execute([
        'id' => $tokenId,
        'token_hash' => hash('sha256', 'rap-p0-01-unit-access-' . $tokenId),
        'subject_id' => $userId,
        'company_id' => $companyId,
        'session_id' => $sessionId,
    ]);

    $pdo->prepare(
        'INSERT INTO refresh_tokens (
            id, token_hash, device_session_id, company_id, user_id, expires_at
         ) VALUES (
            :id, :token_hash, :session_id, :company_id, :user_id, now() + interval \'30 days\'
         )',
    )->execute([
        'id' => $refreshId,
        'token_hash' => hash('sha256', 'rap-p0-01-unit-refresh-' . $refreshId),
        'session_id' => $sessionId,
        'company_id' => $companyId,
        'user_id' => $userId,
    ]);

    // Second active device/session/token — must survive revoke of the first device
    $pdo->prepare(
        'INSERT INTO devices (
            id, company_id, installation_id, device_fingerprint, platform,
            device_name, os_name, status, row_version
         ) VALUES (
            :id, :company_id, :installation_id, :fp, \'android\',
            \'RAP-P0-01 Other\', \'Android\', \'active\', 1
         )',
    )->execute([
        'id' => $otherDeviceId,
        'company_id' => $companyId,
        'installation_id' => 'other-' . $installId,
        'fp' => 'sha256:rap-p0-01-other-' . $installId,
    ]);
    $pdo->prepare(
        'INSERT INTO device_sessions (
            id, device_id, company_id, branch_id, user_id, session_type, expires_at
         ) VALUES (
            :id, :device_id, :company_id, :branch_id, :user_id, \'user\', now() + interval \'30 days\'
         )',
    )->execute([
        'id' => $otherSessionId,
        'device_id' => $otherDeviceId,
        'company_id' => $companyId,
        'branch_id' => $branchId,
        'user_id' => $userId,
    ]);
    $pdo->prepare(
        'INSERT INTO api_tokens (
            id, token_hash, subject_type, subject_id, company_id, device_session_id, scopes, expires_at
         ) VALUES (
            :id, :token_hash, \'user\', :subject_id, :company_id, :session_id,
            ARRAY[\'sync:push\']::text[], now() + interval \'15 minutes\'
         )',
    )->execute([
        'id' => $otherTokenId,
        'token_hash' => hash('sha256', 'rap-p0-01-other-access-' . $otherTokenId),
        'subject_id' => $userId,
        'company_id' => $companyId,
        'session_id' => $otherSessionId,
    ]);

    pass('fixtures inserted (target + other active session)');

    $repo->revokeDevice($deviceId);
    pass('AdminRepository::revokeDevice completed');

    $st = $pdo->prepare('SELECT revoked_at IS NOT NULL FROM api_tokens WHERE id = :id');
    $st->execute(['id' => $tokenId]);
    if (!$st->fetchColumn()) {
        fail('target api_token (subject_type=user) still active after revoke');
    }
    pass('target access token revoked');

    $st = $pdo->prepare('SELECT revoked_at IS NOT NULL FROM refresh_tokens WHERE id = :id');
    $st->execute(['id' => $refreshId]);
    if (!$st->fetchColumn()) {
        fail('target refresh_token still active');
    }
    pass('target refresh token revoked');

    $st = $pdo->prepare('SELECT revoked_at IS NOT NULL FROM device_sessions WHERE id = :id');
    $st->execute(['id' => $sessionId]);
    if (!$st->fetchColumn()) {
        fail('target session still active');
    }
    pass('target session revoked');

    $st = $pdo->prepare("SELECT status = 'revoked' AND revoked_at IS NOT NULL FROM devices WHERE id = :id");
    $st->execute(['id' => $deviceId]);
    if (!$st->fetchColumn()) {
        fail('device not marked revoked');
    }
    pass('device marked revoked');

    $st = $pdo->prepare('SELECT revoked_at IS NULL FROM api_tokens WHERE id = :id');
    $st->execute(['id' => $otherTokenId]);
    if (!$st->fetchColumn()) {
        fail('other device access token was incorrectly revoked');
    }
    pass('other active session access token untouched');

    $st = $pdo->prepare("SELECT COUNT(*) FROM api_tokens WHERE id = :id AND subject_type = 'user'");
    $st->execute(['id' => $tokenId]);
    if ((int) $st->fetchColumn() !== 1) {
        fail('fixture is not subject_type=user');
    }
    pass('confirmed revoked token was subject_type=user (old filter would miss it)');
} catch (Throwable $e) {
    fail($e->getMessage());
} finally {
    // Cleanup disposable rows (order respects FKs)
    foreach ([
        ['DELETE FROM api_tokens WHERE id IN (:a, :b)', ['a' => $tokenId, 'b' => $otherTokenId]],
        ['DELETE FROM refresh_tokens WHERE id = :id', ['id' => $refreshId]],
        ['DELETE FROM device_sessions WHERE id IN (:a, :b)', ['a' => $sessionId, 'b' => $otherSessionId]],
        ['DELETE FROM devices WHERE id IN (:a, :b)', ['a' => $deviceId, 'b' => $otherDeviceId]],
    ] as [$sql, $params]) {
        try {
            $pdo->prepare($sql)->execute($params);
        } catch (Throwable) {
            // best-effort cleanup
        }
    }
    pass('fixtures cleaned up');
}

fwrite(STDOUT, "OK RAP-P0-01 unit checks passed\n");
exit(0);
