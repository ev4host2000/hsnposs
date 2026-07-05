<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Devices\Repositories;

use MizaCloud\Core\Database\Repository;
use MizaCloud\Modules\Auth\Support\Uuid;
use MizaCloud\Modules\Devices\Models\DeviceModel;
use PDO;

final class DeviceRepository extends Repository
{
    public function findByInstallationId(string $installationId): ?array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT * FROM devices WHERE installation_id = :installation_id LIMIT 1',
        );
        $stmt->execute(['installation_id' => $installationId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
    }

    public function findById(string $deviceId, ?string $companyId = null): ?array
    {
        $sql = 'SELECT * FROM devices WHERE id = :id';
        $params = ['id' => $deviceId];
        if ($companyId !== null) {
            $sql .= ' AND company_id = :company_id';
            $params['company_id'] = $companyId;
        }
        $sql .= ' LIMIT 1';

        $stmt = $this->db->pdo()->prepare($sql);
        $stmt->execute($params);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
    }

    public function countActiveDevices(string $companyId): int
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT count(*) FROM devices
             WHERE company_id = :company_id AND status = \'active\' AND revoked_at IS NULL',
        );
        $stmt->execute(['company_id' => $companyId]);

        return (int) $stmt->fetchColumn();
    }

    public function maxDevicesForCompany(string $companyId): ?int
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT sp.max_devices
             FROM company_subscriptions cs
             INNER JOIN subscription_plans sp ON sp.id = cs.plan_id
             WHERE cs.company_id = :company_id
               AND cs.status IN (\'trial\', \'active\')
             ORDER BY cs.current_period_end DESC
             LIMIT 1',
        );
        $stmt->execute(['company_id' => $companyId]);
        $value = $stmt->fetchColumn();

        return $value === false ? null : (int) $value;
    }

    public function findCompanyStatus(string $companyId): ?string
    {
        $stmt = $this->db->pdo()->prepare('SELECT status FROM companies WHERE id = :id LIMIT 1');
        $stmt->execute(['id' => $companyId]);
        $status = $stmt->fetchColumn();

        return is_string($status) ? $status : null;
    }

    public function findUserRole(string $userId): ?string
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT role FROM users WHERE id = :id AND deleted_at IS NULL LIMIT 1',
        );
        $stmt->execute(['id' => $userId]);
        $role = $stmt->fetchColumn();

        return is_string($role) ? $role : null;
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

    public function createDevice(DeviceModel $device): string
    {
        $id = $device->id !== '' ? $device->id : Uuid::v4();
        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO devices (
                id, company_id, installation_id, device_fingerprint, platform,
                device_name, os_name, os_user, app_version, status,
                registered_at, last_seen_at, registered_by_user_id
             ) VALUES (
                :id, :company_id, :installation_id, :device_fingerprint, :platform,
                :device_name, :os_name, :os_user, :app_version, :status,
                now(), now(), :registered_by_user_id
             )',
        );
        $stmt->execute([
            'id' => $id,
            'company_id' => $device->companyId,
            'installation_id' => $device->installationId,
            'device_fingerprint' => $device->deviceFingerprint,
            'platform' => $device->platform,
            'device_name' => $device->deviceName,
            'os_name' => $device->osName,
            'os_user' => $device->osUser,
            'app_version' => $device->appVersion,
            'status' => 'active',
            'registered_by_user_id' => $device->registeredByUserId,
        ]);

        return $id;
    }

    public function updateDeviceMetadata(
        string $deviceId,
        string $deviceFingerprint,
        string $platform,
        string $deviceName,
        string $osName,
        ?string $osUser,
        ?string $appVersion,
    ): void {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE devices SET
                device_fingerprint = :device_fingerprint,
                platform = :platform,
                device_name = :device_name,
                os_name = :os_name,
                os_user = :os_user,
                app_version = :app_version,
                last_seen_at = now(),
                row_version = row_version + 1
             WHERE id = :id',
        );
        $stmt->execute([
            'id' => $deviceId,
            'device_fingerprint' => $deviceFingerprint,
            'platform' => $platform,
            'device_name' => $deviceName,
            'os_name' => $osName,
            'os_user' => $osUser,
            'app_version' => $appVersion,
        ]);
    }

    public function touchLastSeen(string $deviceId, ?string $appVersion = null): string
    {
        if ($appVersion !== null && $appVersion !== '') {
            $stmt = $this->db->pdo()->prepare(
                'UPDATE devices SET last_seen_at = now(), app_version = :app_version
                 WHERE id = :id RETURNING last_seen_at::text',
            );
            $stmt->execute(['id' => $deviceId, 'app_version' => $appVersion]);
        } else {
            $stmt = $this->db->pdo()->prepare(
                'UPDATE devices SET last_seen_at = now()
                 WHERE id = :id RETURNING last_seen_at::text',
            );
            $stmt->execute(['id' => $deviceId]);
        }

        return (string) $stmt->fetchColumn();
    }

    public function createDeviceSession(
        string $deviceId,
        string $companyId,
        string $branchId,
        ?string $userId,
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
            'session_type' => 'device',
            'ip_address' => $ipAddress,
            'user_agent' => $userAgent,
            'expires_at' => $expiresAt->format('Y-m-d H:i:sP'),
        ]);

        return $sessionId;
    }

    public function createApiToken(
        string $tokenHash,
        string $subjectType,
        string $subjectId,
        string $companyId,
        string $sessionId,
        array $scopes,
        \DateTimeImmutable $expiresAt,
    ): void {
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
            'id' => Uuid::v4(),
            'token_hash' => $tokenHash,
            'subject_type' => $subjectType,
            'subject_id' => $subjectId,
            'company_id' => $companyId,
            'device_session_id' => $sessionId,
            'scopes' => $this->toPgArray($scopes),
            'expires_at' => $expiresAt->format('Y-m-d H:i:sP'),
        ]);
    }

    public function createRefreshToken(
        string $tokenHash,
        string $sessionId,
        string $companyId,
        ?string $userId,
        \DateTimeImmutable $expiresAt,
    ): void {
        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO refresh_tokens (
                id, token_hash, device_session_id, company_id, user_id, issued_at, expires_at
             ) VALUES (
                :id, :token_hash, :device_session_id, :company_id, :user_id, now(), :expires_at
             )',
        );
        $stmt->execute([
            'id' => Uuid::v4(),
            'token_hash' => $tokenHash,
            'device_session_id' => $sessionId,
            'company_id' => $companyId,
            'user_id' => $userId,
            'expires_at' => $expiresAt->format('Y-m-d H:i:sP'),
        ]);
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
