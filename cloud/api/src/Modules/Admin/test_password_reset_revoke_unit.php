<?php
/**
 * RAP-P0-05 — Password reset revokes owner sessions/tokens via Auth helpers.
 *
 * Covers Ops-style reset + forgot-password-style update without SMTP.
 *
 * Usage:
 *   docker compose … exec -T api php /var/www/html/src/Modules/Admin/test_password_reset_revoke_unit.php
 */
declare(strict_types=1);

$root = dirname(__DIR__, 3);
require_once $root . '/vendor/autoload.php';

use MizaCloud\Core\Database\Connection;
use MizaCloud\Modules\Admin\Repositories\AdminRepository;
use MizaCloud\Modules\Auth\Repositories\AuthRepository;

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

function assertRevoked(PDO $pdo, string $table, string $id, string $label): void
{
    $st = $pdo->prepare("SELECT revoked_at IS NOT NULL FROM {$table} WHERE id = :id");
    $st->execute(['id' => $id]);
    if (!$st->fetchColumn()) {
        fail("{$label} still active");
    }
    pass("{$label} revoked");
}

function assertActive(PDO $pdo, string $table, string $id, string $label): void
{
    $st = $pdo->prepare("SELECT revoked_at IS NULL FROM {$table} WHERE id = :id");
    $st->execute(['id' => $id]);
    if (!$st->fetchColumn()) {
        fail("{$label} was incorrectly revoked");
    }
    pass("{$label} untouched");
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
$adminRepo = new AdminRepository($conn);
$authRepo = new AuthRepository($conn);

$st = $pdo->query(
    "SELECT c.id::text AS company_id, b.id::text AS branch_id
     FROM companies c
     JOIN branches b ON b.company_id = c.id AND b.status = 'active'
     WHERE c.status = 'active'
     ORDER BY c.created_at NULLS LAST
     LIMIT 1",
);
$row = $st->fetch(PDO::FETCH_ASSOC);
if (!$row) {
    fail('need an active company with branch');
}
$companyId = (string) $row['company_id'];
$branchId = (string) $row['branch_id'];

$st = $pdo->prepare(
    "SELECT id::text, email::text, password_hash
     FROM users
     WHERE company_id = :c AND role = 'owner' AND deleted_at IS NULL
     LIMIT 1",
);
$st->execute(['c' => $companyId]);
$owner = $st->fetch(PDO::FETCH_ASSOC);
if (!$owner) {
    fail('need an owner user');
}
$ownerId = (string) $owner['id'];
$ownerEmail = (string) ($owner['email'] ?? '');
$originalHash = (string) $owner['password_hash'];

// Second user in same company (cashier) — must survive owner password reset.
$otherUserId = uuid();
$otherUsername = 'rap_p0_05_' . substr($otherUserId, 0, 8);
$otherHash = password_hash('OtherUser1!', PASSWORD_BCRYPT);

$deviceId = uuid();
$sessionId = uuid();
$tokenId = uuid();
$refreshId = uuid();
$pairingTokenId = uuid();
$otherDeviceId = uuid();
$otherSessionId = uuid();
$otherTokenId = uuid();
$otherRefreshId = uuid();
$installId = uuid();

$cleanup = static function () use (
    $pdo,
    $deviceId,
    $otherDeviceId,
    $sessionId,
    $otherSessionId,
    $tokenId,
    $pairingTokenId,
    $otherTokenId,
    $refreshId,
    $otherRefreshId,
    $otherUserId,
    $ownerId,
    $originalHash,
): void {
    foreach ([$tokenId, $pairingTokenId, $otherTokenId] as $id) {
        $pdo->prepare('DELETE FROM api_tokens WHERE id = :id')->execute(['id' => $id]);
    }
    foreach ([$refreshId, $otherRefreshId] as $id) {
        $pdo->prepare('DELETE FROM refresh_tokens WHERE id = :id')->execute(['id' => $id]);
    }
    foreach ([$sessionId, $otherSessionId] as $id) {
        $pdo->prepare('DELETE FROM device_sessions WHERE id = :id')->execute(['id' => $id]);
    }
    foreach ([$deviceId, $otherDeviceId] as $id) {
        $pdo->prepare('DELETE FROM devices WHERE id = :id')->execute(['id' => $id]);
    }
    $pdo->prepare('DELETE FROM users WHERE id = :id')->execute(['id' => $otherUserId]);
    $pdo->prepare(
        'UPDATE users SET password_hash = :h, updated_at = now(), row_version = row_version + 1 WHERE id = :id',
    )->execute(['h' => $originalHash, 'id' => $ownerId]);
};

try {
    $pdo->prepare(
        'INSERT INTO users (
            id, company_id, default_branch_id, username, email, full_name,
            password_hash, role, account_status, row_version
         ) VALUES (
            :id, :company_id, :branch_id, :username, NULL, \'RAP-P0-05 Other\',
            :password_hash, \'cashier\', \'active\', 1
         )',
    )->execute([
        'id' => $otherUserId,
        'company_id' => $companyId,
        'branch_id' => $branchId,
        'username' => $otherUsername,
        'password_hash' => $otherHash,
    ]);

    $pdo->prepare(
        'INSERT INTO devices (
            id, company_id, installation_id, device_fingerprint, platform,
            device_name, os_name, status, row_version
         ) VALUES (
            :id, :company_id, :installation_id, :fp, \'android\',
            \'RAP-P0-05 Owner\', \'Android\', \'active\', 1
         )',
    )->execute([
        'id' => $deviceId,
        'company_id' => $companyId,
        'installation_id' => $installId,
        'fp' => 'sha256:rap-p0-05-owner-' . $installId,
    ]);

    $pdo->prepare(
        'INSERT INTO devices (
            id, company_id, installation_id, device_fingerprint, platform,
            device_name, os_name, status, row_version
         ) VALUES (
            :id, :company_id, :installation_id, :fp, \'android\',
            \'RAP-P0-05 Other\', \'Android\', \'active\', 1
         )',
    )->execute([
        'id' => $otherDeviceId,
        'company_id' => $companyId,
        'installation_id' => 'other-' . $installId,
        'fp' => 'sha256:rap-p0-05-other-' . $installId,
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
        'user_id' => $ownerId,
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
        'user_id' => $otherUserId,
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
        'token_hash' => hash('sha256', 'rap-p0-05-owner-access-' . $tokenId),
        'subject_id' => $ownerId,
        'company_id' => $companyId,
        'session_id' => $sessionId,
    ]);

    $pdo->prepare(
        'INSERT INTO api_tokens (
            id, token_hash, subject_type, subject_id, company_id, device_session_id, scopes, expires_at
         ) VALUES (
            :id, :token_hash, \'user\', :subject_id, :company_id, NULL,
            ARRAY[\'auth:session\', \'devices:register\']::text[], now() + interval \'15 minutes\'
         )',
    )->execute([
        'id' => $pairingTokenId,
        'token_hash' => hash('sha256', 'rap-p0-05-pairing-' . $pairingTokenId),
        'subject_id' => $ownerId,
        'company_id' => $companyId,
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
        'token_hash' => hash('sha256', 'rap-p0-05-other-access-' . $otherTokenId),
        'subject_id' => $otherUserId,
        'company_id' => $companyId,
        'session_id' => $otherSessionId,
    ]);

    $pdo->prepare(
        'INSERT INTO refresh_tokens (
            id, token_hash, device_session_id, company_id, user_id, expires_at
         ) VALUES (
            :id, :token_hash, :session_id, :company_id, :user_id, now() + interval \'30 days\'
         )',
    )->execute([
        'id' => $refreshId,
        'token_hash' => hash('sha256', 'rap-p0-05-owner-refresh-' . $refreshId),
        'session_id' => $sessionId,
        'company_id' => $companyId,
        'user_id' => $ownerId,
    ]);

    $pdo->prepare(
        'INSERT INTO refresh_tokens (
            id, token_hash, device_session_id, company_id, user_id, expires_at
         ) VALUES (
            :id, :token_hash, :session_id, :company_id, :user_id, now() + interval \'30 days\'
         )',
    )->execute([
        'id' => $otherRefreshId,
        'token_hash' => hash('sha256', 'rap-p0-05-other-refresh-' . $otherRefreshId),
        'session_id' => $otherSessionId,
        'company_id' => $companyId,
        'user_id' => $otherUserId,
    ]);

    pass('fixtures inserted (owner session + pairing + other user)');

    // --- 1) Ops Admin reset path (same sequence as AdminService) ---
    $newOpsPassword = 'OpsResetP0-05!';
    $newOpsHash = password_hash($newOpsPassword, PASSWORD_BCRYPT);
    if ($newOpsHash === false) {
        fail('password_hash failed');
    }

    $owners = $authRepo->findOwnersByCompany($companyId);
    if ($owners === []) {
        fail('findOwnersByCompany returned empty');
    }

    $authRepo->beginTransaction();
    try {
        if (!$adminRepo->resetOwnerPassword($companyId, $newOpsHash)) {
            $authRepo->rollBack();
            fail('AdminRepository::resetOwnerPassword returned false');
        }
        foreach ($owners as $o) {
            $authRepo->revokeUserAccessAfterPasswordChange((string) $o['id'], (string) $o['company_id']);
        }
        $authRepo->commit();
    } catch (Throwable $e) {
        $authRepo->rollBack();
        throw $e;
    }
    pass('Ops reset + Auth revoke completed');

    assertRevoked($pdo, 'device_sessions', $sessionId, 'owner device_session');
    assertRevoked($pdo, 'api_tokens', $tokenId, 'owner access token');
    assertRevoked($pdo, 'refresh_tokens', $refreshId, 'owner refresh token');
    assertRevoked($pdo, 'api_tokens', $pairingTokenId, 'owner pairing token');

    assertActive($pdo, 'device_sessions', $otherSessionId, 'other user session');
    assertActive($pdo, 'api_tokens', $otherTokenId, 'other user access token');
    assertActive($pdo, 'refresh_tokens', $otherRefreshId, 'other user refresh token');

    $st = $pdo->prepare("SELECT status FROM devices WHERE id = :id");
    $st->execute(['id' => $deviceId]);
    if ($st->fetchColumn() !== 'active') {
        fail('owner device status changed by password reset (should stay active)');
    }
    pass('owner device status unchanged (not device revoke)');

    $st = $pdo->prepare('SELECT password_hash FROM users WHERE id = :id');
    $st->execute(['id' => $ownerId]);
    $hashAfterOps = (string) $st->fetchColumn();
    if (!password_verify($newOpsPassword, $hashAfterOps)) {
        fail('owner cannot authenticate with new Ops password');
    }
    pass('owner can authenticate with new Ops password (password_verify)');

    // --- 2) forgot-password path (Auth update + revoke; no SMTP) ---
    // Re-seed owner session/tokens after Ops revoke.
    $sessionId2 = uuid();
    $tokenId2 = uuid();
    $refreshId2 = uuid();
    $pairingTokenId2 = uuid();

    $pdo->prepare(
        'INSERT INTO device_sessions (
            id, device_id, company_id, branch_id, user_id, session_type, expires_at
         ) VALUES (
            :id, :device_id, :company_id, :branch_id, :user_id, \'user\', now() + interval \'30 days\'
         )',
    )->execute([
        'id' => $sessionId2,
        'device_id' => $deviceId,
        'company_id' => $companyId,
        'branch_id' => $branchId,
        'user_id' => $ownerId,
    ]);
    $pdo->prepare(
        'INSERT INTO api_tokens (
            id, token_hash, subject_type, subject_id, company_id, device_session_id, scopes, expires_at
         ) VALUES (
            :id, :token_hash, \'user\', :subject_id, :company_id, :session_id,
            ARRAY[\'sync:push\']::text[], now() + interval \'15 minutes\'
         )',
    )->execute([
        'id' => $tokenId2,
        'token_hash' => hash('sha256', 'rap-p0-05-forgot-access-' . $tokenId2),
        'subject_id' => $ownerId,
        'company_id' => $companyId,
        'session_id' => $sessionId2,
    ]);
    $pdo->prepare(
        'INSERT INTO api_tokens (
            id, token_hash, subject_type, subject_id, company_id, device_session_id, scopes, expires_at
         ) VALUES (
            :id, :token_hash, \'user\', :subject_id, :company_id, NULL,
            ARRAY[\'auth:session\']::text[], now() + interval \'15 minutes\'
         )',
    )->execute([
        'id' => $pairingTokenId2,
        'token_hash' => hash('sha256', 'rap-p0-05-forgot-pairing-' . $pairingTokenId2),
        'subject_id' => $ownerId,
        'company_id' => $companyId,
    ]);
    $pdo->prepare(
        'INSERT INTO refresh_tokens (
            id, token_hash, device_session_id, company_id, user_id, expires_at
         ) VALUES (
            :id, :token_hash, :session_id, :company_id, :user_id, now() + interval \'30 days\'
         )',
    )->execute([
        'id' => $refreshId2,
        'token_hash' => hash('sha256', 'rap-p0-05-forgot-refresh-' . $refreshId2),
        'session_id' => $sessionId2,
        'company_id' => $companyId,
        'user_id' => $ownerId,
    ]);
    pass('re-seeded owner tokens for forgot-password path');

    if ($ownerEmail === '') {
        fail('owner email empty — cannot exercise forgot-password update path');
    }

    $forgotPassword = 'ForgotP0-05!x';
    $forgotHash = password_hash($forgotPassword, PASSWORD_BCRYPT);
    if ($forgotHash === false) {
        fail('forgot password_hash failed');
    }

    $byEmail = $authRepo->findActiveOwnersByEmail($ownerEmail);
    if ($byEmail === []) {
        fail('findActiveOwnersByEmail returned empty for owner email');
    }

    $authRepo->beginTransaction();
    try {
        $updated = $authRepo->updateOwnerPasswordsByEmail($ownerEmail, $forgotHash);
        if ($updated < 1) {
            $authRepo->rollBack();
            fail('updateOwnerPasswordsByEmail updated 0 rows');
        }
        foreach ($byEmail as $o) {
            $authRepo->revokeUserAccessAfterPasswordChange((string) $o['id'], (string) $o['company_id']);
        }
        $authRepo->commit();
    } catch (Throwable $e) {
        $authRepo->rollBack();
        throw $e;
    }
    pass('forgot-password update + Auth revoke completed (no SMTP)');

    assertRevoked($pdo, 'device_sessions', $sessionId2, 'forgot: owner session');
    assertRevoked($pdo, 'api_tokens', $tokenId2, 'forgot: owner access token');
    assertRevoked($pdo, 'refresh_tokens', $refreshId2, 'forgot: owner refresh token');
    assertRevoked($pdo, 'api_tokens', $pairingTokenId2, 'forgot: owner pairing token');

    assertActive($pdo, 'device_sessions', $otherSessionId, 'forgot: other user session still');
    assertActive($pdo, 'api_tokens', $otherTokenId, 'forgot: other user access still');
    assertActive($pdo, 'refresh_tokens', $otherRefreshId, 'forgot: other user refresh still');

    $st = $pdo->prepare('SELECT password_hash FROM users WHERE id = :id');
    $st->execute(['id' => $ownerId]);
    $hashAfterForgot = (string) $st->fetchColumn();
    if (!password_verify($forgotPassword, $hashAfterForgot)) {
        fail('owner cannot authenticate with forgot-password temporary hash');
    }
    pass('owner can authenticate with forgot-password new hash');

    // Cleanup extra forgot fixtures (main cleanup handles first set + other user)
    foreach ([$tokenId2, $pairingTokenId2] as $id) {
        $pdo->prepare('DELETE FROM api_tokens WHERE id = :id')->execute(['id' => $id]);
    }
    $pdo->prepare('DELETE FROM refresh_tokens WHERE id = :id')->execute(['id' => $refreshId2]);
    $pdo->prepare('DELETE FROM device_sessions WHERE id = :id')->execute(['id' => $sessionId2]);

    fwrite(STDOUT, "OK: RAP-P0-05 password reset revoke unit passed\n");
} catch (Throwable $e) {
    fwrite(STDERR, 'ERROR: ' . $e->getMessage() . "\n");
    exit(1);
} finally {
    $cleanup();
}
