<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Admin\Repositories;

use MizaCloud\Core\Database\Repository;
use MizaCloud\Modules\Auth\Support\Uuid;
use PDO;
use Throwable;

/**
 * Read/write repository for ops_audit_events (append-only).
 */
final class OpsAuditRepository extends Repository
{
    /**
     * @param array<string, mixed> $event
     */
    public function insert(array $event): ?string
    {
        $id = (string) ($event['id'] ?? '');
        if ($id === '' || !Uuid::isValid($id)) {
            $id = $this->newUuid();
        }

        $sql = 'INSERT INTO ops_audit_events (
            id, created_at, organization_id, branch_id, user_id, user_name, role_name,
            device_id, installation_id, session_id, request_id, transaction_uuid,
            entity, entity_id, action, status, severity, reason,
            ip_address, user_agent, application_version, platform, trigger_source,
            duration_ms, correlation_id, error_code, error_message, stack_trace,
            request_json, response_json, metadata_json
        ) VALUES (
            :id::uuid,
            COALESCE(NULLIF(:created_at, \'\')::timestamptz, now()),
            NULLIF(:organization_id, \'\')::uuid,
            NULLIF(:branch_id, \'\')::uuid,
            NULLIF(:user_id, \'\')::uuid,
            NULLIF(:user_name, \'\'),
            NULLIF(:role_name, \'\'),
            NULLIF(:device_id, \'\')::uuid,
            NULLIF(:installation_id, \'\'),
            NULLIF(:session_id, \'\'),
            NULLIF(:request_id, \'\'),
            NULLIF(:transaction_uuid, \'\'),
            NULLIF(:entity, \'\'),
            NULLIF(:entity_id, \'\'),
            :action,
            :status,
            :severity,
            NULLIF(:reason, \'\'),
            NULLIF(:ip_address, \'\'),
            NULLIF(:user_agent, \'\'),
            NULLIF(:application_version, \'\'),
            NULLIF(:platform, \'\'),
            NULLIF(:trigger_source, \'\'),
            NULLIF(:duration_ms, \'\')::double precision,
            NULLIF(:correlation_id, \'\'),
            NULLIF(:error_code, \'\'),
            NULLIF(:error_message, \'\'),
            NULLIF(:stack_trace, \'\'),
            CAST(:request_json AS jsonb),
            CAST(:response_json AS jsonb),
            CAST(:metadata_json AS jsonb)
        )';

        $stmt = $this->db->pdo()->prepare($sql);
        $duration = $event['duration_ms'] ?? ($event['duration'] ?? null);
        $stmt->execute([
            'id' => $id,
            'created_at' => (string) ($event['created_at'] ?? ''),
            'organization_id' => (string) ($this->nullableUuid($event['organization_id'] ?? null) ?? ''),
            'branch_id' => (string) ($this->nullableUuid($event['branch_id'] ?? null) ?? ''),
            'user_id' => (string) ($this->nullableUuid($event['user_id'] ?? null) ?? ''),
            'user_name' => (string) ($this->nullableString($event['user_name'] ?? null) ?? ''),
            'role_name' => (string) ($this->nullableString($event['role_name'] ?? ($event['role'] ?? null)) ?? ''),
            'device_id' => (string) ($this->nullableUuid($event['device_id'] ?? null) ?? ''),
            'installation_id' => (string) ($this->nullableString($event['installation_id'] ?? null) ?? ''),
            'session_id' => (string) ($this->nullableString($event['session_id'] ?? null) ?? ''),
            'request_id' => (string) ($this->nullableString($event['request_id'] ?? null) ?? ''),
            'transaction_uuid' => (string) ($this->nullableString($event['transaction_uuid'] ?? null) ?? ''),
            'entity' => (string) ($this->nullableString($event['entity'] ?? null) ?? ''),
            'entity_id' => (string) ($this->nullableString($event['entity_id'] ?? null) ?? ''),
            'action' => (string) ($event['action'] ?? 'unknown'),
            'status' => (string) ($event['status'] ?? 'success'),
            'severity' => (string) ($event['severity'] ?? 'info'),
            'reason' => (string) ($this->nullableString($event['reason'] ?? null) ?? ''),
            'ip_address' => (string) ($this->nullableString($event['ip_address'] ?? null) ?? ''),
            'user_agent' => (string) ($this->nullableString($event['user_agent'] ?? null) ?? ''),
            'application_version' => (string) ($this->nullableString($event['application_version'] ?? null) ?? ''),
            'platform' => (string) ($this->nullableString($event['platform'] ?? null) ?? ''),
            'trigger_source' => (string) ($this->nullableString($event['trigger'] ?? ($event['trigger_source'] ?? null)) ?? ''),
            'duration_ms' => $duration === null || $duration === '' ? '' : (string) (float) $duration,
            'correlation_id' => (string) ($this->nullableString($event['correlation_id'] ?? null) ?? ''),
            'error_code' => (string) ($this->nullableString($event['error_code'] ?? null) ?? ''),
            'error_message' => (string) ($this->nullableString($event['error_message'] ?? null) ?? ''),
            'stack_trace' => (string) ($this->nullableString($event['stack_trace'] ?? null) ?? ''),
            'request_json' => $this->jsonEncode($event['request'] ?? ($event['request_json'] ?? [])),
            'response_json' => $this->jsonEncode($event['response'] ?? ($event['response_json'] ?? [])),
            'metadata_json' => $this->jsonEncode($event['metadata'] ?? ($event['metadata_json'] ?? [])),
        ]);

        return $id;
    }

    /**
     * @param array<string, mixed> $filters
     * @return list<array<string, mixed>>
     */
    public function search(array $filters, int $limit, int $offset, string $sortBy, string $sortDir): array
    {
        [$where, $params] = $this->buildWhere($filters);
        $sortCol = $this->sortColumn($sortBy);
        $dir = strtolower($sortDir) === 'asc' ? 'ASC' : 'DESC';
        $limit = max(1, min($limit, 200));
        $offset = max(0, $offset);

        $sql = "SELECT
                id::text AS id,
                created_at::text AS timestamp_utc,
                organization_id::text AS organization_id,
                branch_id::text AS branch_id,
                user_id::text AS user_id,
                user_name,
                role_name AS role,
                device_id::text AS device_id,
                installation_id,
                session_id,
                request_id,
                transaction_uuid,
                entity,
                entity_id,
                action,
                status,
                severity,
                reason,
                ip_address,
                user_agent,
                application_version,
                platform,
                trigger_source AS trigger,
                duration_ms AS duration,
                correlation_id,
                error_code,
                error_message
             FROM ops_audit_events
             WHERE {$where}
             ORDER BY {$sortCol} {$dir}
             LIMIT :limit OFFSET :offset";

        $stmt = $this->db->pdo()->prepare($sql);
        foreach ($params as $key => $value) {
            $stmt->bindValue(':' . $key, $value);
        }
        $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
        $stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
        $stmt->execute();
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        return is_array($rows) ? $rows : [];
    }

    /** @param array<string, mixed> $filters */
    public function count(array $filters): int
    {
        [$where, $params] = $this->buildWhere($filters);
        $stmt = $this->db->pdo()->prepare("SELECT count(*)::int FROM ops_audit_events WHERE {$where}");
        $stmt->execute($params);

        return (int) $stmt->fetchColumn();
    }

    /** @return array<string, mixed>|null */
    public function findById(string $id): ?array
    {
        if (!Uuid::isValid($id)) {
            return null;
        }

        $stmt = $this->db->pdo()->prepare(
            "SELECT
                id::text AS id,
                created_at::text AS timestamp_utc,
                organization_id::text AS organization_id,
                branch_id::text AS branch_id,
                user_id::text AS user_id,
                user_name,
                role_name AS role,
                device_id::text AS device_id,
                installation_id,
                session_id,
                request_id,
                transaction_uuid,
                entity,
                entity_id,
                action,
                status,
                severity,
                reason,
                ip_address,
                user_agent,
                application_version,
                platform,
                trigger_source AS trigger,
                duration_ms AS duration,
                correlation_id,
                error_code,
                error_message,
                stack_trace,
                request_json,
                response_json,
                metadata_json
             FROM ops_audit_events WHERE id = :id",
        );
        $stmt->execute(['id' => $id]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!is_array($row)) {
            return null;
        }

        $row['request'] = $this->decodeJson($row['request_json'] ?? '{}');
        $row['response'] = $this->decodeJson($row['response_json'] ?? '{}');
        $row['metadata'] = $this->decodeJson($row['metadata_json'] ?? '{}');
        unset($row['request_json'], $row['response_json'], $row['metadata_json']);

        return $row;
    }

    /**
     * @param array<string, mixed> $filters
     * @return list<array<string, mixed>>
     */
    public function exportRows(array $filters, int $maxRows): array
    {
        [$where, $params] = $this->buildWhere($filters);
        $maxRows = max(1, min($maxRows, 20000));
        $sql = "SELECT
                id::text AS id,
                created_at::text AS timestamp_utc,
                organization_id::text AS organization_id,
                branch_id::text AS branch_id,
                user_id::text AS user_id,
                user_name,
                role_name AS role,
                device_id::text AS device_id,
                installation_id,
                session_id,
                request_id,
                transaction_uuid,
                entity,
                entity_id,
                action,
                status,
                severity,
                reason,
                ip_address,
                user_agent,
                application_version,
                platform,
                trigger_source AS trigger,
                duration_ms AS duration,
                correlation_id,
                error_code,
                error_message,
                metadata_json::text AS metadata_json
             FROM ops_audit_events
             WHERE {$where}
             ORDER BY created_at DESC
             LIMIT {$maxRows}";
        $stmt = $this->db->pdo()->prepare($sql);
        $stmt->execute($params);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        return is_array($rows) ? $rows : [];
    }

    /** @return array{days:int, archive_enabled:bool} */
    public function getRetention(): array
    {
        try {
            $stmt = $this->db->pdo()->query(
                "SELECT value_json FROM ops_audit_settings WHERE key = 'retention'",
            );
            $raw = $stmt?->fetchColumn();
            $decoded = is_string($raw) ? json_decode($raw, true) : [];
            if (!is_array($decoded)) {
                $decoded = [];
            }

            return [
                'days' => (int) ($decoded['days'] ?? 90),
                'archive_enabled' => (bool) ($decoded['archive_enabled'] ?? true),
            ];
        } catch (Throwable) {
            return ['days' => 90, 'archive_enabled' => true];
        }
    }

    public function setRetention(int $days, bool $archiveEnabled): array
    {
        $days = in_array($days, [90, 180, 365], true) ? $days : 90;
        $payload = json_encode([
            'days' => $days,
            'archive_enabled' => $archiveEnabled,
        ], JSON_UNESCAPED_UNICODE);
        $stmt = $this->db->pdo()->prepare(
            "INSERT INTO ops_audit_settings (key, value_json, updated_at)
             VALUES ('retention', CAST(:v AS jsonb), now())
             ON CONFLICT (key) DO UPDATE
             SET value_json = EXCLUDED.value_json, updated_at = now()",
        );
        $stmt->execute(['v' => $payload]);

        return ['days' => $days, 'archive_enabled' => $archiveEnabled];
    }

    public function runRetentionArchive(?int $days = null): array
    {
        $retention = $this->getRetention();
        $useDays = $days ?? (int) $retention['days'];
        if (!($retention['archive_enabled'] ?? true)) {
            return ['archived' => 0, 'days' => $useDays, 'skipped' => true];
        }

        $stmt = $this->db->pdo()->prepare('SELECT ops_audit_archive_older_than(:days)');
        $stmt->execute(['days' => $useDays]);
        $archived = (int) $stmt->fetchColumn();

        return ['archived' => $archived, 'days' => $useDays, 'skipped' => false];
    }

    /**
     * @param array<string, int> $thresholds
     * @return list<array<string, mixed>>
     */
    public function securityAlerts(array $thresholds, int $windowMinutes): array
    {
        $windowMinutes = max(5, min($windowMinutes, 24 * 60));
        $map = [
            'organization.mismatch' => ['key' => 'organization_mismatch', 'label' => 'Organization Mismatch'],
            'auth.login_failed' => ['key' => 'login_failed', 'label' => 'Failed Login'],
            'sync.failed' => ['key' => 'sync_failed', 'label' => 'Sync Failed'],
            'security.unauthorized' => ['key' => 'unauthorized', 'label' => 'Unauthorized Request'],
        ];

        $alerts = [];
        foreach ($map as $action => $meta) {
            $threshold = (int) ($thresholds[$meta['key']] ?? 0);
            if ($threshold < 1) {
                continue;
            }
            $stmt = $this->db->pdo()->prepare(
                "SELECT count(*)::int FROM ops_audit_events
                 WHERE action = :action
                   AND created_at >= now() - make_interval(mins => :mins)",
            );
            $stmt->execute(['action' => $action, 'mins' => $windowMinutes]);
            $count = (int) $stmt->fetchColumn();
            if ($count >= $threshold) {
                $alerts[] = [
                    'severity' => 'critical',
                    'code' => $meta['key'],
                    'message' => $meta['label'] . ' exceeded threshold',
                    'action' => $action,
                    'count' => $count,
                    'threshold' => $threshold,
                    'window_minutes' => $windowMinutes,
                ];
            }
        }

        return $alerts;
    }

    /**
     * @param array<string, mixed> $filters
     * @return array{0:string,1:array<string,mixed>}
     */
    private function buildWhere(array $filters): array
    {
        $where = ['1=1'];
        $params = [];

        if (($filters['q'] ?? '') !== '') {
            $where[] = '(action ILIKE :q OR entity ILIKE :q OR user_name ILIKE :q OR reason ILIKE :q OR error_code ILIKE :q)';
            $params['q'] = '%' . $filters['q'] . '%';
        }
        if (($filters['organization_id'] ?? '') !== '') {
            $where[] = 'organization_id = :organization_id';
            $params['organization_id'] = $filters['organization_id'];
        }
        if (($filters['branch_id'] ?? '') !== '') {
            $where[] = 'branch_id = :branch_id';
            $params['branch_id'] = $filters['branch_id'];
        }
        if (($filters['user_id'] ?? '') !== '') {
            $where[] = 'user_id = :user_id';
            $params['user_id'] = $filters['user_id'];
        }
        if (($filters['device_id'] ?? '') !== '') {
            $where[] = 'device_id = :device_id';
            $params['device_id'] = $filters['device_id'];
        }
        if (($filters['entity'] ?? '') !== '') {
            $where[] = 'entity = :entity';
            $params['entity'] = $filters['entity'];
        }
        if (($filters['action'] ?? '') !== '') {
            $where[] = 'action ILIKE :action';
            $params['action'] = '%' . $filters['action'] . '%';
        }
        if (($filters['status'] ?? '') !== '') {
            $where[] = 'status = :status';
            $params['status'] = $filters['status'];
        }
        if (($filters['severity'] ?? '') !== '') {
            $where[] = 'severity = :severity';
            $params['severity'] = $filters['severity'];
        }
        if (($filters['error_code'] ?? '') !== '') {
            $where[] = 'error_code ILIKE :error_code';
            $params['error_code'] = '%' . $filters['error_code'] . '%';
        }
        if (($filters['date_from'] ?? '') !== '') {
            $where[] = 'created_at >= :date_from::timestamptz';
            $params['date_from'] = $filters['date_from'] . (str_contains((string) $filters['date_from'], 'T') ? '' : ' 00:00:00+00');
        }
        if (($filters['date_to'] ?? '') !== '') {
            $where[] = 'created_at <= :date_to::timestamptz';
            $params['date_to'] = $filters['date_to'] . (str_contains((string) $filters['date_to'], 'T') ? '' : ' 23:59:59+00');
        }

        return [implode(' AND ', $where), $params];
    }

    private function sortColumn(string $sortBy): string
    {
        return match ($sortBy) {
            'action' => 'action',
            'status' => 'status',
            'severity' => 'severity',
            'entity' => 'entity',
            'user_name' => 'user_name',
            'organization_id' => 'organization_id',
            default => 'created_at',
        };
    }

    private function nullableUuid(mixed $value): ?string
    {
        $s = trim((string) ($value ?? ''));
        if ($s === '' || !Uuid::isValid($s)) {
            return null;
        }

        return $s;
    }

    private function nullableString(mixed $value): ?string
    {
        if ($value === null) {
            return null;
        }
        $s = trim((string) $value);

        return $s === '' ? null : $s;
    }

    private function jsonEncode(mixed $value): string
    {
        if (is_string($value)) {
            $decoded = json_decode($value, true);
            if (is_array($decoded)) {
                $value = $decoded;
            } else {
                $value = ['raw' => $value];
            }
        }
        if (!is_array($value)) {
            $value = [];
        }

        return json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '{}';
    }

    /** @return array<string, mixed> */
    private function decodeJson(mixed $value): array
    {
        if (is_array($value)) {
            return $value;
        }
        if (!is_string($value) || $value === '') {
            return [];
        }
        $decoded = json_decode($value, true);

        return is_array($decoded) ? $decoded : [];
    }

    private function newUuid(): string
    {
        $data = random_bytes(16);
        $data[6] = chr((ord($data[6]) & 0x0f) | 0x40);
        $data[8] = chr((ord($data[8]) & 0x3f) | 0x80);

        return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($data), 4));
    }
}
