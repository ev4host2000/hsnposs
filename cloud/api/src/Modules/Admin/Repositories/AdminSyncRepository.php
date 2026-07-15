<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Admin\Repositories;

use MizaCloud\Core\Database\Repository;
use PDO;

final class AdminSyncRepository extends Repository
{
    /** @return array<string, mixed> */
    public function globalOverview(): array
    {
        $stmt = $this->db->pdo()->query(
            'SELECT
                (SELECT count(*)::int FROM sync_queue WHERE status = \'pending\') AS pending_queue,
                (SELECT count(*)::int FROM sync_queue WHERE status IN (\'rejected\', \'conflict\')) AS failed_queue,
                (SELECT count(*)::int FROM sync_conflicts WHERE status = \'pending\') AS pending_conflicts,
                (SELECT count(*)::int FROM devices
                    WHERE status = \'active\'
                      AND revoked_at IS NULL
                      AND last_seen_at < now() - interval \'24 hours\') AS stale_devices,
                (SELECT max(occurred_at)::text FROM sync_changelog) AS last_changelog_at',
        );
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : [];
    }

    /** @return array<string, mixed> */
    public function companySyncHealth(string $companyId): array
    {
        $pdo = $this->db->pdo();

        $queueStmt = $pdo->prepare(
            'SELECT status, count(*)::int AS total
             FROM sync_queue
             WHERE company_id = :company_id
             GROUP BY status',
        );
        $queueStmt->execute(['company_id' => $companyId]);
        $queueRows = $queueStmt->fetchAll(PDO::FETCH_ASSOC);
        $queueStats = [];
        if (is_array($queueRows)) {
            foreach ($queueRows as $row) {
                $queueStats[(string) $row['status']] = (int) $row['total'];
            }
        }

        $conflictStmt = $pdo->prepare(
            'SELECT
                count(*) FILTER (WHERE status = \'pending\')::int AS pending,
                count(*) FILTER (WHERE status = \'resolved\')::int AS resolved
             FROM sync_conflicts
             WHERE company_id = :company_id',
        );
        $conflictStmt->execute(['company_id' => $companyId]);
        $conflictStats = $conflictStmt->fetch(PDO::FETCH_ASSOC) ?: ['pending' => 0, 'resolved' => 0];

        $changelogStmt = $pdo->prepare(
            'SELECT
                max(occurred_at)::text AS last_occurred_at,
                max(sequence)::bigint AS last_sequence,
                count(*)::int AS total_events
             FROM sync_changelog
             WHERE company_id = :company_id',
        );
        $changelogStmt->execute(['company_id' => $companyId]);
        $changelogSummary = $changelogStmt->fetch(PDO::FETCH_ASSOC) ?: [];

        $recentStmt = $pdo->prepare(
            'SELECT
                sequence,
                entity_type,
                entity_id::text AS entity_id,
                operation,
                occurred_at::text AS occurred_at,
                origin_device_id::text AS origin_device_id
             FROM sync_changelog
             WHERE company_id = :company_id
             ORDER BY sequence DESC
             LIMIT 15',
        );
        $recentStmt->execute(['company_id' => $companyId]);
        $recentEvents = $recentStmt->fetchAll(PDO::FETCH_ASSOC);

        $devicesStmt = $pdo->prepare(
            'SELECT
                id::text AS id,
                device_name,
                platform,
                app_version,
                status,
                last_seen_at::text AS last_seen_at,
                revoked_at::text AS revoked_at,
                (last_seen_at < now() - interval \'24 hours\') AS is_stale
             FROM devices
             WHERE company_id = :company_id
             ORDER BY last_seen_at DESC NULLS LAST',
        );
        $devicesStmt->execute(['company_id' => $companyId]);
        $devices = $devicesStmt->fetchAll(PDO::FETCH_ASSOC);

        return [
            'queue' => $queueStats,
            'conflicts' => [
                'pending' => (int) ($conflictStats['pending'] ?? 0),
                'resolved' => (int) ($conflictStats['resolved'] ?? 0),
            ],
            'changelog' => [
                'last_occurred_at' => $changelogSummary['last_occurred_at'] ?? null,
                'last_sequence' => isset($changelogSummary['last_sequence'])
                    ? (int) $changelogSummary['last_sequence']
                    : null,
                'total_events' => (int) ($changelogSummary['total_events'] ?? 0),
                'recent' => is_array($recentEvents) ? $recentEvents : [],
            ],
            'devices' => is_array($devices) ? $devices : [],
        ];
    }

    /** @return list<array<string, mixed>> */
    public function listFailures(?string $companyId, int $limit = 50): array
    {
        $limit = max(1, min($limit, 200));
        $sql = 'SELECT
                sq.id::text AS id,
                sq.company_id::text AS company_id,
                c.name AS company_name,
                sq.device_id::text AS device_id,
                d.device_name,
                sq.entity_type,
                sq.entity_id::text AS entity_id,
                sq.operation,
                sq.status,
                sq.error_code,
                sq.error_detail,
                sq.received_at::text AS received_at,
                sq.processed_at::text AS processed_at
             FROM sync_queue sq
             INNER JOIN companies c ON c.id = sq.company_id
             LEFT JOIN devices d ON d.id = sq.device_id
             WHERE sq.status IN (\'rejected\', \'conflict\')';
        $params = [];

        if ($companyId !== null && $companyId !== '') {
            $sql .= ' AND sq.company_id = :company_id';
            $params['company_id'] = $companyId;
        }

        $sql .= ' ORDER BY sq.received_at DESC LIMIT :limit';

        $stmt = $this->db->pdo()->prepare($sql);
        foreach ($params as $key => $value) {
            $stmt->bindValue(':' . $key, $value);
        }
        $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
        $stmt->execute();
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        return is_array($rows) ? $rows : [];
    }

    /** @return list<array<string, mixed>> */
    public function listConflicts(?string $companyId, ?string $status, int $limit = 50): array
    {
        $limit = max(1, min($limit, 200));
        $sql = 'SELECT
                sc.id::text AS id,
                sc.company_id::text AS company_id,
                c.name AS company_name,
                sc.device_id::text AS device_id,
                d.device_name,
                sc.entity_type,
                sc.entity_id::text AS entity_id,
                sc.operation,
                sc.conflict_kind,
                sc.status,
                sc.resolution,
                sc.client_row_version,
                sc.server_row_version,
                sc.created_at::text AS created_at,
                sc.resolved_at::text AS resolved_at
             FROM sync_conflicts sc
             INNER JOIN companies c ON c.id = sc.company_id
             LEFT JOIN devices d ON d.id = sc.device_id
             WHERE 1=1';
        $params = [];

        if ($companyId !== null && $companyId !== '') {
            $sql .= ' AND sc.company_id = :company_id';
            $params['company_id'] = $companyId;
        }

        if ($status !== null && $status !== '') {
            $sql .= ' AND sc.status = :status';
            $params['status'] = $status;
        }

        $sql .= ' ORDER BY sc.created_at DESC LIMIT :limit';

        $stmt = $this->db->pdo()->prepare($sql);
        foreach ($params as $key => $value) {
            $stmt->bindValue(':' . $key, $value);
        }
        $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
        $stmt->execute();
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        return is_array($rows) ? $rows : [];
    }

    /** @return list<array<string, mixed>> */
    public function listStaleDevices(int $limit = 50): array
    {
        $limit = max(1, min($limit, 200));
        $stmt = $this->db->pdo()->prepare(
            'SELECT
                d.id::text AS id,
                d.company_id::text AS company_id,
                c.name AS company_name,
                d.device_name,
                d.platform,
                d.app_version,
                d.last_seen_at::text AS last_seen_at
             FROM devices d
             INNER JOIN companies c ON c.id = d.company_id
             WHERE d.status = \'active\'
               AND d.revoked_at IS NULL
               AND d.last_seen_at < now() - interval \'24 hours\'
             ORDER BY d.last_seen_at ASC
             LIMIT :limit',
        );
        $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
        $stmt->execute();
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        return is_array($rows) ? $rows : [];
    }
}
