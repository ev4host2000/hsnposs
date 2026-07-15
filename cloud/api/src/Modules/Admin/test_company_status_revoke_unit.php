<?php
/**
 * RAP-P0-02 — Company status suspend/close revokes tenant access + refresh tokens.
 *
 * Usage:
 *   docker compose … exec -T api php /var/www/html/src/Modules/Admin/test_company_status_revoke_unit.php
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

$companies = $pdo->query(
    "SELECT id::text FROM companies WHERE status = 'active' ORDER BY created_at NULLS LAST LIMIT 2",
)->fetchAll(PDO::FETCH_COLUMN);
if (count($companies) < 1) {
    fail('need at least one active company');
}
$companyId = (string) $companies[0];
$otherCompanyId = isset($companies[1]) ? (string) $companies[1] : null;

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

$originalStatus = 'active';
$deviceId = uuid();
$sessionId = uuid();
$tokenId = uuid();
$refreshId = uuid();
$pairingTokenId = uuid();
$otherTokenId = $otherCompanyId ? uuid() : null;
$newTokenId = null;
$closedTokenId = null;
$installId = uuid();

$restoreCompany = static function () use ($pdo, $companyId, $originalStatus): void {
    $pdo->prepare(
        'UPDATE companies SET status = :status, updated_at = now(), row_version = row_version + 1 WHERE id = :id',
    )->execute(['id' => $companyId, 'status' => $originalStatus]);
};

try {
    $pdo->prepare(
        'INSERT INTO devices (
            id, company_id, installation_id, device_fingerprint, platform,
            device_name, os_name, status, row_version
         ) VALUES (
            :id, :company_id, :installation_id, :fp, \'android\',
            \'RAP-P0-02 Unit\', \'Android\', \'active\', 1
         )',
    )->execute([
        'id' => $deviceId,
        'company_id' => $companyId,
        'installation_id' => $installId,
        'fp' => 'sha256:rap-p0-02-unit-' . $installId,
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
        'token_hash' => hash('sha256', 'rap-p0-02-access-' . $tokenId),
        'subject_id' => $userId,
        'company_id' => $companyId,
        'session_id' => $sessionId,
    ]);

    // Pairing-style access token (no device_session_id) — must also be revoked on suspend
    $pdo->prepare(
        'INSERT INTO api_tokens (
            id, token_hash, subject_type, subject_id, company_id, device_session_id, scopes, expires_at
         ) VALUES (
            :id, :token_hash, \'user\', :subject_id, :company_id, NULL,
            ARRAY[\'auth:session\',\'devices:register\']::text[], now() + interval \'15 minutes\'
         )',
    )->execute([
        'id' => $pairingTokenId,
        'token_hash' => hash('sha256', 'rap-p0-02-pairing-' . $pairingTokenId),
        'subject_id' => $userId,
        'company_id' => $companyId,
    ]);

    $pdo->prepare(
        'INSERT INTO refresh_tokens (
            id, token_hash, device_session_id, company_id, user_id, expires_at
         ) VALUES (
            :id, :token_hash, :session_id, :company_id, :user_id, now() + interval \'30 days\'
         )',
    )->execute([
        'id' => $refreshId,
        'token_hash' => hash('sha256', 'rap-p0-02-refresh-' . $refreshId),
        'session_id' => $sessionId,
        'company_id' => $companyId,
        'user_id' => $userId,
    ]);

    if ($otherCompanyId && $otherTokenId) {
        $st = $pdo->prepare("SELECT id::text FROM users WHERE company_id = :c AND account_status = 'active' LIMIT 1");
        $st->execute(['c' => $otherCompanyId]);
        $otherUserId = $st->fetchColumn() ?: $userId;
        $pdo->prepare(
            'INSERT INTO api_tokens (
                id, token_hash, subject_type, subject_id, company_id, device_session_id, scopes, expires_at
             ) VALUES (
                :id, :token_hash, \'user\', :subject_id, :company_id, NULL,
                ARRAY[\'sync:push\']::text[], now() + interval \'15 minutes\'
             )',
        )->execute([
            'id' => $otherTokenId,
            'token_hash' => hash('sha256', 'rap-p0-02-other-' . $otherTokenId),
            'subject_id' => $otherUserId,
            'company_id' => $otherCompanyId,
        ]);
        pass('fixture token for other active company inserted');
    } else {
        pass('single-company env — skip cross-tenant token fixture');
    }

    pass('fixtures inserted for target company');

    if (!$repo->updateCompanyStatus($companyId, 'suspended')) {
        fail('updateCompanyStatus(suspended) returned false');
    }
    pass('company suspended');

    $st = $pdo->prepare('SELECT revoked_at IS NOT NULL FROM api_tokens WHERE id = :id');
    $st->execute(['id' => $tokenId]);
    if (!$st->fetchColumn()) {
        fail('session access token still active after suspend');
    }
    pass('access token revoked after suspend');

    $st->execute(['id' => $pairingTokenId]);
    if (!$st->fetchColumn()) {
        fail('pairing access token still active after suspend');
    }
    pass('pairing access token revoked after suspend');

    $st = $pdo->prepare('SELECT revoked_at IS NOT NULL FROM refresh_tokens WHERE id = :id');
    $st->execute(['id' => $refreshId]);
    if (!$st->fetchColumn()) {
        fail('refresh token still active after suspend');
    }
    pass('refresh token revoked after suspend');

    $st = $pdo->prepare('SELECT revoked_at IS NOT NULL FROM device_sessions WHERE id = :id');
    $st->execute(['id' => $sessionId]);
    if (!$st->fetchColumn()) {
        fail('device session still active after suspend');
    }
    pass('device session revoked after suspend');

    if ($otherTokenId) {
        $st = $pdo->prepare('SELECT revoked_at IS NULL FROM api_tokens WHERE id = :id');
        $st->execute(['id' => $otherTokenId]);
        if (!$st->fetchColumn()) {
            fail('other company token was incorrectly revoked');
        }
        pass('other active company token untouched');
    }

    if (!$repo->updateCompanyStatus($companyId, 'active')) {
        fail('updateCompanyStatus(active) returned false');
    }
    pass('company reactivated');

    // Previously revoked tokens must stay revoked (clients must re-login)
    $st = $pdo->prepare('SELECT revoked_at IS NOT NULL FROM api_tokens WHERE id = :id');
    $st->execute(['id' => $tokenId]);
    if (!$st->fetchColumn()) {
        fail('old access token was incorrectly restored on reactivate');
    }
    pass('old access token remains revoked after reactivate');

    $st = $pdo->prepare('SELECT revoked_at IS NOT NULL FROM refresh_tokens WHERE id = :id');
    $st->execute(['id' => $refreshId]);
    if (!$st->fetchColumn()) {
        fail('old refresh token was incorrectly restored on reactivate');
    }
    pass('old refresh token remains revoked after reactivate');

    // New token after reactivate must stay live (active tenant unaffected going forward)
    $newTokenId = uuid();
    $pdo->prepare(
        'INSERT INTO api_tokens (
            id, token_hash, subject_type, subject_id, company_id, device_session_id, scopes, expires_at
         ) VALUES (
            :id, :token_hash, \'user\', :subject_id, :company_id, NULL,
            ARRAY[\'sync:push\']::text[], now() + interval \'15 minutes\'
         )',
    )->execute([
        'id' => $newTokenId,
        'token_hash' => hash('sha256', 'rap-p0-02-new-' . $newTokenId),
        'subject_id' => $userId,
        'company_id' => $companyId,
    ]);
    $st = $pdo->prepare('SELECT revoked_at IS NULL FROM api_tokens WHERE id = :id');
    $st->execute(['id' => $newTokenId]);
    if (!$st->fetchColumn()) {
        fail('new token after reactivate is not active');
    }
    pass('new access token after reactivate stays active');

    // closed also revokes
    $closedTokenId = uuid();
    $pdo->prepare(
        'INSERT INTO api_tokens (
            id, token_hash, subject_type, subject_id, company_id, device_session_id, scopes, expires_at
         ) VALUES (
            :id, :token_hash, \'user\', :subject_id, :company_id, NULL,
            ARRAY[\'sync:push\']::text[], now() + interval \'15 minutes\'
         )',
    )->execute([
        'id' => $closedTokenId,
        'token_hash' => hash('sha256', 'rap-p0-02-closed-' . $closedTokenId),
        'subject_id' => $userId,
        'company_id' => $companyId,
    ]);
    if (!$repo->updateCompanyStatus($companyId, 'closed')) {
        fail('updateCompanyStatus(closed) returned false');
    }
    $st->execute(['id' => $closedTokenId]);
    // after close, revoked_at should be NOT null — reuse query correctly
    $st2 = $pdo->prepare('SELECT revoked_at IS NOT NULL FROM api_tokens WHERE id = :id');
    $st2->execute(['id' => $closedTokenId]);
    if (!$st2->fetchColumn()) {
        fail('token not revoked on company closed');
    }
    pass('access token revoked on company closed');

    $st2->execute(['id' => $newTokenId]);
    if (!$st2->fetchColumn()) {
        fail('post-reactivate token not revoked on close');
    }
    pass('prior live token revoked on company closed');
} catch (Throwable $e) {
    fail($e->getMessage());
} finally {
    $restoreCompany();
    pass('company status restored to active');

    $ids = array_values(array_filter([
        $tokenId,
        $pairingTokenId,
        $otherTokenId,
        $newTokenId ?? null,
        $closedTokenId ?? null,
    ]));
    if ($ids !== []) {
        $in = implode(',', array_fill(0, count($ids), '?'));
        try {
            $pdo->prepare("DELETE FROM api_tokens WHERE id IN ($in)")->execute($ids);
        } catch (Throwable) {
        }
    }
    try {
        $pdo->prepare('DELETE FROM refresh_tokens WHERE id = :id')->execute(['id' => $refreshId]);
    } catch (Throwable) {
    }
    try {
        $pdo->prepare('DELETE FROM device_sessions WHERE id = :id')->execute(['id' => $sessionId]);
    } catch (Throwable) {
    }
    try {
        $pdo->prepare('DELETE FROM devices WHERE id = :id')->execute(['id' => $deviceId]);
    } catch (Throwable) {
    }
    pass('fixtures cleaned up');
}

$st = $pdo->prepare('SELECT status FROM companies WHERE id = :id');
$st->execute(['id' => $companyId]);
if ($st->fetchColumn() !== 'active') {
    fail('company was not left active after test');
}
pass('target company left active');

fwrite(STDOUT, "OK RAP-P0-02 company-status unit checks passed\n");
exit(0);
