<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Devices\Models;

final class DeviceModel
{
    /** @param array<string, mixed> $row */
    public static function fromRow(array $row, bool $isSelf = false): self
    {
        return new self(
            id: (string) $row['id'],
            companyId: (string) $row['company_id'],
            installationId: (string) $row['installation_id'],
            deviceFingerprint: (string) $row['device_fingerprint'],
            platform: (string) $row['platform'],
            deviceName: (string) $row['device_name'],
            osName: (string) $row['os_name'],
            osUser: $row['os_user'] !== null ? (string) $row['os_user'] : null,
            appVersion: $row['app_version'] !== null ? (string) $row['app_version'] : null,
            status: (string) $row['status'],
            registeredAt: (string) $row['registered_at'],
            lastSeenAt: $row['last_seen_at'] !== null ? (string) $row['last_seen_at'] : null,
            revokedAt: $row['revoked_at'] !== null ? (string) $row['revoked_at'] : null,
            registeredByUserId: $row['registered_by_user_id'] !== null ? (string) $row['registered_by_user_id'] : null,
            rowVersion: (int) ($row['row_version'] ?? 0),
            isSelf: $isSelf,
        );
    }

    public function __construct(
        public readonly string $id,
        public readonly string $companyId,
        public readonly string $installationId,
        public readonly string $deviceFingerprint,
        public readonly string $platform,
        public readonly string $deviceName,
        public readonly string $osName,
        public readonly ?string $osUser,
        public readonly ?string $appVersion,
        public readonly string $status,
        public readonly string $registeredAt,
        public readonly ?string $lastSeenAt,
        public readonly ?string $revokedAt,
        public readonly ?string $registeredByUserId,
        public readonly int $rowVersion,
        public readonly bool $isSelf = false,
    ) {}

    /** @return array<string, mixed> */
    public function toArray(bool $includeFingerprint = false): array
    {
        $data = [
            'id' => $this->id,
            'device_id' => $this->id,
            'company_id' => $this->companyId,
            'installation_id' => $this->installationId,
            'platform' => $this->platform,
            'device_name' => $this->deviceName,
            'os_name' => $this->osName,
            'status' => $this->status,
            'registered_at' => $this->formatTimestamp($this->registeredAt),
            'last_seen_at' => $this->lastSeenAt !== null ? $this->formatTimestamp($this->lastSeenAt) : null,
            'revoked_at' => $this->revokedAt !== null ? $this->formatTimestamp($this->revokedAt) : null,
            'row_version' => $this->rowVersion,
            'is_self' => $this->isSelf,
        ];

        if ($includeFingerprint) {
            $data['device_fingerprint'] = $this->deviceFingerprint;
        }
        if ($this->osUser !== null) {
            $data['os_user'] = $this->osUser;
        }
        if ($this->appVersion !== null) {
            $data['app_version'] = $this->appVersion;
        }
        if ($this->registeredByUserId !== null) {
            $data['registered_by_user_id'] = $this->registeredByUserId;
        }

        return $data;
    }

    private function formatTimestamp(string $value): string
    {
        $time = strtotime($value);
        if ($time === false) {
            return $value;
        }

        return gmdate('Y-m-d\TH:i:s.v\Z', $time);
    }
}
