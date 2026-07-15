<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Auth\Repositories;

use MizaCloud\Core\Database\Repository;
use MizaCloud\Modules\Auth\Models\UserModel;
use MizaCloud\Modules\Auth\Support\Uuid;
use PDO;

final class AuthRepository extends Repository
{
    public function findCompanyStatus(string $companyId): ?string
    {
        $stmt = $this->db->pdo()->prepare('SELECT status FROM companies WHERE id = :id LIMIT 1');
        $stmt->execute(['id' => $companyId]);
        $status = $stmt->fetchColumn();

        return is_string($status) ? $status : null;
    }

    public function findBranch(string $companyId, string $branchId): ?array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT id, company_id, status FROM branches WHERE id = :id AND company_id = :company_id LIMIT 1',
        );
        $stmt->execute(['id' => $branchId, 'company_id' => $companyId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
    }

    public function findUserForLogin(string $companyId, string $login): ?UserModel
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT id, company_id, default_branch_id, username, full_name, role, account_status, password_hash
             FROM users
             WHERE company_id = :company_id
               AND deleted_at IS NULL
               AND (lower(username) = lower(:login) OR lower(email::text) = lower(:login))
             LIMIT 1',
        );
        $stmt->execute(['company_id' => $companyId, 'login' => $login]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? UserModel::fromRow($row) : null;
    }

    public function findUserById(string $userId): ?UserModel
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT id, company_id, default_branch_id, username, full_name, role, account_status, password_hash
             FROM users WHERE id = :id AND deleted_at IS NULL LIMIT 1',
        );
        $stmt->execute(['id' => $userId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? UserModel::fromRow($row) : null;
    }

    public function userHasBranchAccess(string $userId, string $branchId, string $companyId): bool
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT 1 FROM user_branch_access
             WHERE user_id = :user_id AND branch_id = :branch_id AND company_id = :company_id
             LIMIT 1',
        );
        $stmt->execute([
            'user_id' => $userId,
            'branch_id' => $branchId,
            'company_id' => $companyId,
        ]);

        if ($stmt->fetchColumn() !== false) {
            return true;
        }

        $user = $this->findUserById($userId);

        return $user !== null && $user->defaultBranchId === $branchId;
    }

    public function findDevice(string $deviceId, string $companyId, string $installationId): ?array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT id, company_id, installation_id, status, revoked_at
             FROM devices
             WHERE id = :id AND company_id = :company_id AND installation_id = :installation_id
             LIMIT 1',
        );
        $stmt->execute([
            'id' => $deviceId,
            'company_id' => $companyId,
            'installation_id' => $installationId,
        ]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
    }

    public function findDeviceByInstallation(string $companyId, string $installationId): ?array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT id, company_id, installation_id, status, revoked_at
             FROM devices
             WHERE company_id = :company_id AND installation_id = :installation_id
             LIMIT 1',
        );
        $stmt->execute([
            'company_id' => $companyId,
            'installation_id' => $installationId,
        ]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
    }

    /** @return array<string, mixed>|null */
    public function findDeviceByInstallationGlobal(string $installationId): ?array
    {
        if ($installationId === '') {
            return null;
        }

        $stmt = $this->db->pdo()->prepare(
            'SELECT id, company_id, installation_id, status, revoked_at
             FROM devices
             WHERE installation_id = :installation_id
             ORDER BY last_seen_at DESC NULLS LAST
             LIMIT 1',
        );
        $stmt->execute(['installation_id' => $installationId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
    }

    /** @return list<array<string, mixed>> */
    public function findLoginAccountsByEmail(string $email): array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT
                u.id::text AS user_id,
                u.company_id::text AS company_id,
                u.default_branch_id::text AS branch_id,
                u.email::text AS email,
                u.password_hash,
                u.account_status,
                c.name AS company_name,
                c.status AS company_status
             FROM users u
             INNER JOIN companies c ON c.id = u.company_id
             WHERE lower(u.email::text) = lower(:email)
               AND u.deleted_at IS NULL
               AND u.role IN (\'owner\', \'admin\', \'manager\', \'cashier\')
             ORDER BY c.name ASC',
        );
        $stmt->execute(['email' => trim($email)]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        return is_array($rows) ? $rows : [];
    }

    /**
     * Owners matching forgot-password update criteria (email + active owner).
     *
     * @return list<array{id: string, company_id: string}>
     */
    public function findActiveOwnersByEmail(string $email): array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT id::text AS id, company_id::text AS company_id
             FROM users
             WHERE lower(email::text) = lower(:email)
               AND deleted_at IS NULL
               AND role = \'owner\'
               AND account_status = \'active\'',
        );
        $stmt->execute(['email' => trim($email)]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        return is_array($rows) ? $rows : [];
    }

    /**
     * Owners matching Ops reset-password update criteria (company + owner).
     *
     * @return list<array{id: string, company_id: string}>
     */
    public function findOwnersByCompany(string $companyId): array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT id::text AS id, company_id::text AS company_id
             FROM users
             WHERE company_id = :company_id
               AND deleted_at IS NULL
               AND role = \'owner\'',
        );
        $stmt->execute(['company_id' => $companyId]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        return is_array($rows) ? $rows : [];
    }

    public function updateOwnerPasswordsByEmail(string $email, string $passwordHash): int
    {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE users
             SET password_hash = :password_hash,
                 updated_at = now(),
                 row_version = row_version + 1
             WHERE lower(email::text) = lower(:email)
               AND deleted_at IS NULL
               AND role = \'owner\'
               AND account_status = \'active\'',
        );
        $stmt->execute([
            'email' => trim($email),
            'password_hash' => $passwordHash,
        ]);

        return $stmt->rowCount();
    }

    public function touchDeviceLastSeen(string $deviceId): void
    {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE devices SET last_seen_at = now() WHERE id = :id',
        );
        $stmt->execute(['id' => $deviceId]);
    }

    public function createUserSession(
        string $deviceId,
        string $companyId,
        string $branchId,
        string $userId,
        ?string $ipAddress,
        ?string $userAgent,
        \DateTimeImmutable $expiresAt,
    ): string {
        $sessionId = Uuid::v4();
        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO device_sessions (
                id, device_id, company_id, branch_id, user_id, session_type,
                ip_address, user_agent, created_at, last_active_at, expires_at
             ) VALUES (
                :id, :device_id, :company_id, :branch_id, :user_id, :session_type,
                :ip_address, :user_agent, now(), now(), :expires_at
             )',
        );
        $stmt->execute([
            'id' => $sessionId,
            'device_id' => $deviceId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'user_id' => $userId,
            'session_type' => 'user',
            'ip_address' => $ipAddress,
            'user_agent' => $userAgent,
            'expires_at' => $expiresAt->format('Y-m-d H:i:sP'),
        ]);

        return $sessionId;
    }

    public function findSession(string $sessionId): ?array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT ds.*, d.status AS device_status, d.revoked_at AS device_revoked_at
             FROM device_sessions ds
             INNER JOIN devices d ON d.id = ds.device_id
             WHERE ds.id = :id
             LIMIT 1',
        );
        $stmt->execute(['id' => $sessionId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
    }

    public function touchSession(string $sessionId): void
    {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE device_sessions SET last_active_at = now() WHERE id = :id AND revoked_at IS NULL',
        );
        $stmt->execute(['id' => $sessionId]);
    }

    public function createApiToken(
        string $tokenHash,
        string $userId,
        string $companyId,
        ?string $sessionId,
        array $scopes,
        \DateTimeImmutable $expiresAt,
    ): string {
        $tokenId = Uuid::v4();
        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO api_tokens (
                id, token_hash, subject_type, subject_id, company_id, device_session_id,
                scopes, issued_at, expires_at
             ) VALUES (
                :id, :token_hash, :subject_type, :subject_id, :company_id, :device_session_id,
                :scopes, now(), :expires_at
             )',
        );
        $stmt->execute([
            'id' => $tokenId,
            'token_hash' => $tokenHash,
            'subject_type' => 'user',
            'subject_id' => $userId,
            'company_id' => $companyId,
            'device_session_id' => $sessionId,
            'scopes' => $this->toPgArray($scopes),
            'expires_at' => $expiresAt->format('Y-m-d H:i:sP'),
        ]);

        return $tokenId;
    }

    public function createRefreshToken(
        string $tokenHash,
        string $sessionId,
        string $companyId,
        string $userId,
        \DateTimeImmutable $expiresAt,
    ): string {
        $tokenId = Uuid::v4();
        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO refresh_tokens (
                id, token_hash, device_session_id, company_id, user_id, issued_at, expires_at
             ) VALUES (
                :id, :token_hash, :device_session_id, :company_id, :user_id, now(), :expires_at
             )',
        );
        $stmt->execute([
            'id' => $tokenId,
            'token_hash' => $tokenHash,
            'device_session_id' => $sessionId,
            'company_id' => $companyId,
            'user_id' => $userId,
            'expires_at' => $expiresAt->format('Y-m-d H:i:sP'),
        ]);

        return $tokenId;
    }

    public function findRefreshTokenByHash(string $tokenHash): ?array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT rt.*, ds.device_id, ds.revoked_at AS session_revoked_at,
                    d.status AS device_status, d.revoked_at AS device_revoked_at
             FROM refresh_tokens rt
             INNER JOIN device_sessions ds ON ds.id = rt.device_session_id
             INNER JOIN devices d ON d.id = ds.device_id
             WHERE rt.token_hash = :token_hash
             LIMIT 1',
        );
        $stmt->execute(['token_hash' => $tokenHash]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
    }

    public function markRefreshTokenReplaced(string $tokenId, string $replacedById): void
    {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE refresh_tokens
             SET revoked_at = now(), replaced_by_id = :replaced_by_id
             WHERE id = :id',
        );
        $stmt->execute(['id' => $tokenId, 'replaced_by_id' => $replacedById]);
    }

    public function revokeRefreshToken(string $tokenId): void
    {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE refresh_tokens SET revoked_at = now() WHERE id = :id AND revoked_at IS NULL',
        );
        $stmt->execute(['id' => $tokenId]);
    }

    public function findApiTokenByHash(string $tokenHash): ?array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT * FROM api_tokens WHERE token_hash = :token_hash LIMIT 1',
        );
        $stmt->execute(['token_hash' => $tokenHash]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
    }

    /** @param list<string> $scopes */
    public function createPlatformAdminToken(
        string $tokenId,
        string $tokenHash,
        array $scopes,
        \DateTimeImmutable $expiresAt,
    ): void {
        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO platform_admin_tokens (
                id, token_hash, scopes, issued_at, expires_at
             ) VALUES (
                :id, :token_hash, :scopes, now(), :expires_at
             )',
        );
        $stmt->execute([
            'id' => $tokenId,
            'token_hash' => $tokenHash,
            'scopes' => $this->toPgArray($scopes),
            'expires_at' => $expiresAt->format('Y-m-d H:i:sP'),
        ]);
    }

    public function findPlatformAdminTokenByHash(string $tokenHash): ?array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT * FROM platform_admin_tokens WHERE token_hash = :token_hash LIMIT 1',
        );
        $stmt->execute(['token_hash' => $tokenHash]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
    }

    public function revokePlatformAdminTokenByHash(string $tokenHash): void
    {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE platform_admin_tokens
             SET revoked_at = now()
             WHERE token_hash = :token_hash AND revoked_at IS NULL',
        );
        $stmt->execute(['token_hash' => $tokenHash]);
    }

    public function revokeAllActivePlatformAdminTokens(): void
    {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE platform_admin_tokens
             SET revoked_at = now()
             WHERE revoked_at IS NULL',
        );
        $stmt->execute();
    }

    public function revokeApiTokensForSession(string $sessionId): void
    {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE api_tokens SET revoked_at = now()
             WHERE device_session_id = :session_id AND revoked_at IS NULL',
        );
        $stmt->execute(['session_id' => $sessionId]);
    }

    public function revokeSession(string $sessionId): void
    {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE device_sessions SET revoked_at = now() WHERE id = :id AND revoked_at IS NULL',
        );
        $stmt->execute(['id' => $sessionId]);
    }

    public function revokeRefreshTokensForSession(string $sessionId): void
    {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE refresh_tokens SET revoked_at = now()
             WHERE device_session_id = :session_id AND revoked_at IS NULL',
        );
        $stmt->execute(['session_id' => $sessionId]);
    }

    public function revokeAllUserSessions(string $userId, string $companyId): void
    {
        $pdo = $this->db->pdo();
        $stmt = $pdo->prepare(
            'SELECT id FROM device_sessions
             WHERE user_id = :user_id AND company_id = :company_id AND revoked_at IS NULL',
        );
        $stmt->execute(['user_id' => $userId, 'company_id' => $companyId]);
        $sessionIds = $stmt->fetchAll(PDO::FETCH_COLUMN);

        foreach ($sessionIds as $sessionId) {
            $this->revokeSession((string) $sessionId);
            $this->revokeApiTokensForSession((string) $sessionId);
            $this->revokeRefreshTokensForSession((string) $sessionId);
        }
    }

    /**
     * RAP-P0-05: pairing / orphan access tokens (no device_session_id) for one user in a company.
     * Narrower than company-wide revoke (P0-02).
     */
    public function revokeOrphanApiTokensForUser(string $userId, string $companyId): void
    {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE api_tokens SET revoked_at = now()
             WHERE subject_type = \'user\'
               AND subject_id = :user_id
               AND company_id = :company_id
               AND device_session_id IS NULL
               AND revoked_at IS NULL',
        );
        $stmt->execute([
            'user_id' => $userId,
            'company_id' => $companyId,
        ]);
    }

    /** RAP-P0-05: full credential-session kill for one user after password change. */
    public function revokeUserAccessAfterPasswordChange(string $userId, string $companyId): void
    {
        $this->revokeAllUserSessions($userId, $companyId);
        $this->revokeOrphanApiTokensForUser($userId, $companyId);
    }

    public function updateUserLastLogin(string $userId): void
    {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE users SET last_login_at = now(), updated_at = now() WHERE id = :id',
        );
        $stmt->execute(['id' => $userId]);
    }

    public function beginTransaction(): void
    {
        $this->db->pdo()->beginTransaction();
    }

    public function commit(): void
    {
        $this->db->pdo()->commit();
    }

    public function rollBack(): void
    {
        if ($this->db->pdo()->inTransaction()) {
            $this->db->pdo()->rollBack();
        }
    }

    /** @param list<string> $scopes */
    private function toPgArray(array $scopes): string
    {
        if ($scopes === []) {
            return '{}';
        }

        $escaped = array_map(
            static fn (string $scope): string => '"' . str_replace(['\\', '"'], ['\\\\', '\\"'], $scope) . '"',
            $scopes,
        );

        return '{' . implode(',', $escaped) . '}';
    }
}
