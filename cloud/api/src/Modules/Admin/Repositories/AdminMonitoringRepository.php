<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Admin\Repositories;

use MizaCloud\Core\Database\Repository;
use PDO;
use Throwable;

/**
 * Read-only monitoring aggregations for Admin Ops.
 * Does not mutate any business data.
 */
final class AdminMonitoringRepository extends Repository
{
    /**
     * @param array{
     *   company_id?: string|null,
     *   branch_id?: string|null,
     *   device_id?: string|null,
     *   date_from?: string|null,
     *   date_to?: string|null,
     *   sync_type?: string|null,
     *   status?: string|null
     * } $filters
     * @return array<string, mixed>
     */
    public function snapshot(array $filters = []): array
    {
        $companyId = $this->nonEmpty($filters['company_id'] ?? null);
        $branchId = $this->nonEmpty($filters['branch_id'] ?? null);
        $deviceId = $this->nonEmpty($filters['device_id'] ?? null);
        $dateFrom = $this->nonEmpty($filters['date_from'] ?? null) ?? gmdate('Y-m-d');
        $dateTo = $this->nonEmpty($filters['date_to'] ?? null) ?? gmdate('Y-m-d');
        $syncType = $this->nonEmpty($filters['sync_type'] ?? null);
        $status = $this->nonEmpty($filters['status'] ?? null);

        $started = microtime(true);
        $database = $this->probeDatabase();
        $queue = $this->queueStats($companyId, $branchId, $deviceId, $syncType, $status);
        $syncToday = $this->syncTimelineStats($companyId, $branchId, $deviceId, $dateFrom, $dateTo, $syncType);
        $outbox = $this->outboxStats($companyId, $branchId, $deviceId, $syncType, $status);
        $errors = $this->errorStats($companyId, $deviceId, $dateFrom, $dateTo);
        $performance = $this->performanceStats($companyId, $deviceId, $dateFrom, $dateTo);
        $security = $this->securityStats($companyId, $dateFrom, $dateTo);
        $organizations = $this->organizationsTable($companyId);
        $charts = $this->charts($companyId, $dateFrom, $dateTo);
        $devicesOnline = $this->devicePresence();

        $cloudUp = $database['connected'] === true;
        $queueHealthy = ((int) ($queue['failed'] ?? 0)) < 50;
        $syncHealthy = ((int) ($syncToday['failed'] ?? 0)) < 20;

        $health = [
            'cloud' => $this->healthCard($cloudUp ? 'up' : 'down', $cloudUp ? 'متصل' : 'غير متصل', $database['latency_ms']),
            'database' => $this->healthCard(
                $database['connected'] ? 'up' : 'down',
                $database['connected'] ? 'متصل' : 'غير متصل',
                $database['latency_ms'],
            ),
            'queue' => $this->healthCard(
                $queueHealthy ? 'up' : 'down',
                $queueHealthy ? 'طبيعي' : 'تراكم أخطاء',
                null,
                ['pending' => $queue['pending'] ?? 0, 'failed' => $queue['failed'] ?? 0],
            ),
            'sync_service' => $this->healthCard(
                $syncHealthy ? 'up' : 'degraded',
                $syncHealthy ? 'يعمل' : 'فشل مرتفع',
                null,
                ['successful' => $syncToday['successful'] ?? 0, 'failed' => $syncToday['failed'] ?? 0],
            ),
            'active_workers' => $this->healthCard(
                'up',
                (string) ((int) ($queue['processing'] ?? 0)),
                null,
                ['processing' => $queue['processing'] ?? 0],
            ),
            'connected_devices' => $this->healthCard(
                'up',
                (string) ((int) ($devicesOnline['online'] ?? 0)),
                null,
                $devicesOnline,
            ),
            'online_organizations' => $this->healthCard(
                'up',
                (string) ((int) ($devicesOnline['online_organizations'] ?? 0)),
                null,
                ['count' => $devicesOnline['online_organizations'] ?? 0],
            ),
        ];

        $alerts = [];
        if (((int) ($outbox['failed'] ?? 0)) > 50) {
            $alerts[] = [
                'severity' => 'critical',
                'code' => 'outbox_failed_threshold',
                'message' => 'Outbox Failed > 50',
                'value' => (int) $outbox['failed'],
            ];
        }
        if (((int) ($security['organization_mismatch'] ?? 0)) > 0) {
            $alerts[] = [
                'severity' => 'critical',
                'code' => 'organization_mismatch',
                'message' => 'Organization Mismatch detected',
                'value' => (int) $security['organization_mismatch'],
            ];
        }
        if (((int) ($errors['timeout'] ?? 0)) > 0) {
            $alerts[] = [
                'severity' => 'critical',
                'code' => 'sync_timeout',
                'message' => 'Sync Timeout events',
                'value' => (int) $errors['timeout'],
            ];
        }
        if (!$cloudUp) {
            $alerts[] = [
                'severity' => 'critical',
                'code' => 'cloud_offline',
                'message' => 'Cloud Offline',
                'value' => 1,
            ];
        }
        if (!$database['connected']) {
            $alerts[] = [
                'severity' => 'critical',
                'code' => 'database_offline',
                'message' => 'Database Offline',
                'value' => 1,
            ];
        }

        return [
            'timestamp' => gmdate('Y-m-d\TH:i:s\Z'),
            'generated_in_ms' => round((microtime(true) - $started) * 1000, 2),
            'filters' => [
                'company_id' => $companyId,
                'branch_id' => $branchId,
                'device_id' => $deviceId,
                'date_from' => $dateFrom,
                'date_to' => $dateTo,
                'sync_type' => $syncType,
                'status' => $status,
            ],
            'health' => $health,
            'synchronization' => $syncToday,
            'outbox' => $outbox,
            'errors' => $errors,
            'performance' => $performance,
            'security' => $security,
            'organizations' => $organizations,
            'charts' => $charts,
            'alerts' => $alerts,
            'meta' => [
                'note' => 'Client-only events (SQLite Busy / Global Sync Lock / Tenant Bind) appear when recorded in audit_logs or sync_queue.error_code.',
            ],
        ];
    }

    /** @return array<string, mixed> */
    private function probeDatabase(): array
    {
        $started = microtime(true);
        try {
            $pdo = $this->db->pdo();
            $pdo->query('SELECT 1');

            return [
                'connected' => true,
                'latency_ms' => round((microtime(true) - $started) * 1000, 2),
            ];
        } catch (Throwable) {
            return [
                'connected' => false,
                'latency_ms' => null,
            ];
        }
    }

    /**
     * @param array<string, mixed>|null $extra
     * @return array<string, mixed>
     */
    private function healthCard(string $state, string $label, ?float $latencyMs, ?array $extra = null): array
    {
        $color = match ($state) {
            'up' => 'green',
            'degraded' => 'amber',
            default => 'red',
        };

        return [
            'state' => $state,
            'label' => $label,
            'color' => $color,
            'latency_ms' => $latencyMs,
            'updated_at' => gmdate('Y-m-d\TH:i:s\Z'),
            'extra' => $extra ?? [],
        ];
    }

    /** @return array<string, int> */
    private function queueStats(
        ?string $companyId,
        ?string $branchId,
        ?string $deviceId,
        ?string $syncType,
        ?string $status,
    ): array {
        [$where, $params] = $this->queueFilters($companyId, $branchId, $deviceId, $syncType, $status);
        $sql = "SELECT
            count(*) FILTER (WHERE status = 'pending')::int AS pending,
            count(*) FILTER (WHERE status IN ('rejected', 'conflict'))::int AS failed,
            count(*) FILTER (WHERE status = 'processing')::int AS processing,
            count(*) FILTER (WHERE status = 'accepted')::int AS accepted
         FROM sync_queue WHERE {$where}";
        $stmt = $this->db->pdo()->prepare($sql);
        $stmt->execute($params);
        $row = $stmt->fetch(PDO::FETCH_ASSOC) ?: [];

        return [
            'pending' => (int) ($row['pending'] ?? 0),
            'failed' => (int) ($row['failed'] ?? 0),
            'processing' => (int) ($row['processing'] ?? 0),
            'accepted' => (int) ($row['accepted'] ?? 0),
        ];
    }

    /** @return array<string, mixed> */
    private function syncTimelineStats(
        ?string $companyId,
        ?string $branchId,
        ?string $deviceId,
        string $dateFrom,
        string $dateTo,
        ?string $syncType,
    ): array {
        [$whereChangelog, $paramsChangelog] = $this->changelogFilters(
            $companyId,
            $branchId,
            $deviceId,
            $dateFrom,
            $dateTo,
            $syncType,
        );
        $stmt = $this->db->pdo()->prepare(
            "SELECT count(*)::int AS total
             FROM sync_changelog WHERE {$whereChangelog}",
        );
        $stmt->execute($paramsChangelog);
        $totalEvents = (int) $stmt->fetchColumn();

        [$whereQ, $paramsQ] = $this->queueFilters($companyId, $branchId, $deviceId, $syncType, null);
        $paramsQ['date_from'] = $dateFrom . ' 00:00:00+00';
        $paramsQ['date_to'] = $dateTo . ' 23:59:59+00';
        $stmtQ = $this->db->pdo()->prepare(
            "SELECT
                count(*)::int AS total,
                count(*) FILTER (WHERE status = 'accepted')::int AS successful,
                count(*) FILTER (WHERE status IN ('rejected', 'conflict'))::int AS failed,
                count(*) FILTER (WHERE status = 'pending')::int AS queued,
                count(*) FILTER (WHERE status = 'processing')::int AS running,
                count(*) FILTER (WHERE status = 'conflict')::int AS partial,
                avg(EXTRACT(EPOCH FROM (COALESCE(processed_at, now()) - received_at)))
                    FILTER (WHERE processed_at IS NOT NULL) AS avg_seconds,
                max(EXTRACT(EPOCH FROM (COALESCE(processed_at, now()) - received_at)))
                    FILTER (WHERE processed_at IS NOT NULL) AS max_seconds
             FROM sync_queue
             WHERE {$whereQ}
               AND received_at >= :date_from::timestamptz
               AND received_at <= :date_to::timestamptz",
        );
        $stmtQ->execute($paramsQ);
        $row = $stmtQ->fetch(PDO::FETCH_ASSOC) ?: [];

        $hours = max(1.0, (strtotime($dateTo . ' UTC') - strtotime($dateFrom . ' UTC')) / 3600 + 24);
        $total = (int) ($row['total'] ?? 0);
        $avgSeconds = isset($row['avg_seconds']) ? round((float) $row['avg_seconds'], 2) : null;
        $maxSeconds = isset($row['max_seconds']) ? round((float) $row['max_seconds'], 2) : null;

        return [
            'total_today' => $total,
            'successful' => (int) ($row['successful'] ?? 0),
            'failed' => (int) ($row['failed'] ?? 0),
            'partial' => (int) ($row['partial'] ?? 0),
            'running' => (int) ($row['running'] ?? 0),
            'queued' => (int) ($row['queued'] ?? 0),
            'average_sync_time_seconds' => $avgSeconds,
            'longest_sync_seconds' => $maxSeconds,
            'sync_per_minute' => round($total / max(1.0, $hours * 60), 3),
            'sync_per_hour' => round($total / $hours, 3),
            'changelog_events' => $totalEvents,
        ];
    }

    /** @return array<string, mixed> */
    private function outboxStats(
        ?string $companyId,
        ?string $branchId,
        ?string $deviceId,
        ?string $syncType,
        ?string $status,
    ): array {
        [$where, $params] = $this->queueFilters($companyId, $branchId, $deviceId, $syncType, $status);
        $stmt = $this->db->pdo()->prepare(
            "SELECT
                count(*) FILTER (WHERE status = 'pending')::int AS pending,
                count(*) FILTER (WHERE status IN ('rejected', 'conflict'))::int AS failed,
                count(*) FILTER (WHERE status = 'pending' AND received_at < now() - interval '15 minutes')::int AS retry_queue,
                count(*) FILTER (WHERE status IN ('rejected', 'conflict')
                    AND received_at < now() - interval '24 hours')::int AS dead_queue,
                min(received_at) FILTER (WHERE status = 'pending')::text AS oldest_pending
             FROM sync_queue WHERE {$where}",
        );
        $stmt->execute($params);
        $row = $stmt->fetch(PDO::FETCH_ASSOC) ?: [];

        $topEntityStmt = $this->db->pdo()->prepare(
            "SELECT entity_type, count(*)::int AS total
             FROM sync_queue
             WHERE {$where} AND status IN ('rejected', 'conflict')
             GROUP BY entity_type
             ORDER BY total DESC
             LIMIT 1",
        );
        $topEntityStmt->execute($params);
        $topEntity = $topEntityStmt->fetch(PDO::FETCH_ASSOC) ?: null;

        $topReasonStmt = $this->db->pdo()->prepare(
            "SELECT COALESCE(NULLIF(error_code, ''), 'unknown') AS reason, count(*)::int AS total
             FROM sync_queue
             WHERE {$where} AND status IN ('rejected', 'conflict')
             GROUP BY 1
             ORDER BY total DESC
             LIMIT 1",
        );
        $topReasonStmt->execute($params);
        $topReason = $topReasonStmt->fetch(PDO::FETCH_ASSOC) ?: null;

        return [
            'pending' => (int) ($row['pending'] ?? 0),
            'failed' => (int) ($row['failed'] ?? 0),
            'retry_queue' => (int) ($row['retry_queue'] ?? 0),
            'dead_queue' => (int) ($row['dead_queue'] ?? 0),
            'average_retry_count' => null,
            'oldest_pending_at' => $row['oldest_pending'] ?? null,
            'top_failed_entity' => $topEntity
                ? ['entity_type' => (string) $topEntity['entity_type'], 'count' => (int) $topEntity['total']]
                : null,
            'top_failure_reason' => $topReason
                ? ['reason' => (string) $topReason['reason'], 'count' => (int) $topReason['total']]
                : null,
        ];
    }

    /** @return array<string, int> */
    private function errorStats(
        ?string $companyId,
        ?string $deviceId,
        string $dateFrom,
        string $dateTo,
    ): array {
        $keys = [
            'http_422' => 0,
            'http_401' => 0,
            'http_403' => 0,
            'http_500' => 0,
            'sqlite_busy' => 0,
            'timeout' => 0,
            'organization_mismatch' => 0,
            'tenant_bind_failure' => 0,
            'cursor_reset' => 0,
            'pull_deferred' => 0,
            'global_sync_lock_busy' => 0,
        ];

        $params = [
            'date_from' => $dateFrom . ' 00:00:00+00',
            'date_to' => $dateTo . ' 23:59:59+00',
        ];
        $where = 'received_at >= :date_from::timestamptz AND received_at <= :date_to::timestamptz';
        if ($companyId !== null) {
            $where .= ' AND company_id = :company_id';
            $params['company_id'] = $companyId;
        }
        if ($deviceId !== null) {
            $where .= ' AND device_id = :device_id';
            $params['device_id'] = $deviceId;
        }

        $stmt = $this->db->pdo()->prepare(
            "SELECT lower(coalesce(error_code, '')) AS code, count(*)::int AS total
             FROM sync_queue
             WHERE {$where} AND status IN ('rejected', 'conflict')
             GROUP BY 1",
        );
        $stmt->execute($params);
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) ?: [] as $row) {
            $code = (string) ($row['code'] ?? '');
            $total = (int) ($row['total'] ?? 0);
            if (str_contains($code, '422') || str_contains($code, 'validation')) {
                $keys['http_422'] += $total;
            }
            if (str_contains($code, '401') || str_contains($code, 'unauthorized')) {
                $keys['http_401'] += $total;
            }
            if (str_contains($code, '403') || str_contains($code, 'forbidden')) {
                $keys['http_403'] += $total;
            }
            if (str_contains($code, '500') || str_contains($code, 'server')) {
                $keys['http_500'] += $total;
            }
            if (str_contains($code, 'sqlite') || str_contains($code, 'busy')) {
                $keys['sqlite_busy'] += $total;
            }
            if (str_contains($code, 'timeout')) {
                $keys['timeout'] += $total;
            }
            if (str_contains($code, 'organization_mismatch')) {
                $keys['organization_mismatch'] += $total;
            }
            if (str_contains($code, 'tenant_bind')) {
                $keys['tenant_bind_failure'] += $total;
            }
            if (str_contains($code, 'cursor')) {
                $keys['cursor_reset'] += $total;
            }
            if (str_contains($code, 'deferred')) {
                $keys['pull_deferred'] += $total;
            }
            if (str_contains($code, 'global_sync_lock') || str_contains($code, 'lock_busy')) {
                $keys['global_sync_lock_busy'] += $total;
            }
        }

        $auditParams = [
            'date_from' => $dateFrom . ' 00:00:00+00',
            'date_to' => $dateTo . ' 23:59:59+00',
        ];
        $auditWhere = 'created_at >= :date_from::timestamptz AND created_at <= :date_to::timestamptz';
        if ($companyId !== null) {
            $auditWhere .= ' AND company_id = :company_id';
            $auditParams['company_id'] = $companyId;
        }
        $auditStmt = $this->db->pdo()->prepare(
            "SELECT lower(action) AS action, count(*)::int AS total
             FROM audit_logs
             WHERE {$auditWhere}
             GROUP BY 1",
        );
        $auditStmt->execute($auditParams);
        foreach ($auditStmt->fetchAll(PDO::FETCH_ASSOC) ?: [] as $row) {
            $action = (string) ($row['action'] ?? '');
            $total = (int) ($row['total'] ?? 0);
            if (str_contains($action, 'organization_mismatch')) {
                $keys['organization_mismatch'] += $total;
            }
            if (str_contains($action, 'tenant_bind')) {
                $keys['tenant_bind_failure'] += $total;
            }
            if (str_contains($action, 'cursor_reset')) {
                $keys['cursor_reset'] += $total;
            }
            if (str_contains($action, 'global_sync_lock')) {
                $keys['global_sync_lock_busy'] += $total;
            }
            if (str_contains($action, 'pull_deferred')) {
                $keys['pull_deferred'] += $total;
            }
        }

        return $keys;
    }

    /** @return array<string, mixed> */
    private function performanceStats(
        ?string $companyId,
        ?string $deviceId,
        string $dateFrom,
        string $dateTo,
    ): array {
        $params = [
            'date_from' => $dateFrom . ' 00:00:00+00',
            'date_to' => $dateTo . ' 23:59:59+00',
        ];
        $where = 'received_at >= :date_from::timestamptz AND received_at <= :date_to::timestamptz AND processed_at IS NOT NULL';
        if ($companyId !== null) {
            $where .= ' AND company_id = :company_id';
            $params['company_id'] = $companyId;
        }
        if ($deviceId !== null) {
            $where .= ' AND device_id = :device_id';
            $params['device_id'] = $deviceId;
        }

        $stmt = $this->db->pdo()->prepare(
            "SELECT
                avg(EXTRACT(EPOCH FROM (processed_at - received_at))) AS avg_seconds,
                percentile_cont(0.5) WITHIN GROUP (
                    ORDER BY EXTRACT(EPOCH FROM (processed_at - received_at))
                ) AS p50_seconds
             FROM sync_queue WHERE {$where}",
        );
        try {
            $stmt->execute($params);
            $row = $stmt->fetch(PDO::FETCH_ASSOC) ?: [];
        } catch (Throwable) {
            $stmt = $this->db->pdo()->prepare(
                "SELECT avg(EXTRACT(EPOCH FROM (processed_at - received_at))) AS avg_seconds
                 FROM sync_queue WHERE {$where}",
            );
            $stmt->execute($params);
            $row = $stmt->fetch(PDO::FETCH_ASSOC) ?: [];
        }

        $slowOrgStmt = $this->db->pdo()->prepare(
            "SELECT c.name AS name,
                    avg(EXTRACT(EPOCH FROM (sq.processed_at - sq.received_at))) AS avg_seconds
             FROM sync_queue sq
             INNER JOIN companies c ON c.id = sq.company_id
             WHERE {$where}
             GROUP BY c.name
             ORDER BY avg_seconds DESC NULLS LAST
             LIMIT 1",
        );
        $slowOrgStmt->execute($params);
        $slowOrg = $slowOrgStmt->fetch(PDO::FETCH_ASSOC) ?: null;

        $slowDeviceStmt = $this->db->pdo()->prepare(
            "SELECT coalesce(d.device_name, sq.device_id::text) AS name,
                    avg(EXTRACT(EPOCH FROM (sq.processed_at - sq.received_at))) AS avg_seconds
             FROM sync_queue sq
             LEFT JOIN devices d ON d.id = sq.device_id
             WHERE {$where}
             GROUP BY 1
             ORDER BY avg_seconds DESC NULLS LAST
             LIMIT 1",
        );
        $slowDeviceStmt->execute($params);
        $slowDevice = $slowDeviceStmt->fetch(PDO::FETCH_ASSOC) ?: null;

        $avg = isset($row['avg_seconds']) ? round((float) $row['avg_seconds'], 3) : null;

        return [
            'average_push_duration_seconds' => $avg,
            'average_pull_duration_seconds' => null,
            'average_api_response_seconds' => $avg,
            'average_sqlite_transaction_seconds' => null,
            'average_queue_processing_seconds' => $avg,
            'average_upload_speed' => null,
            'average_download_speed' => null,
            'slowest_organization' => $slowOrg
                ? [
                    'name' => (string) $slowOrg['name'],
                    'avg_seconds' => round((float) $slowOrg['avg_seconds'], 3),
                ]
                : null,
            'slowest_device' => $slowDevice
                ? [
                    'name' => (string) $slowDevice['name'],
                    'avg_seconds' => round((float) $slowDevice['avg_seconds'], 3),
                ]
                : null,
        ];
    }

    /** @return array<string, int> */
    private function securityStats(?string $companyId, string $dateFrom, string $dateTo): array
    {
        $params = [
            'date_from' => $dateFrom . ' 00:00:00+00',
            'date_to' => $dateTo . ' 23:59:59+00',
        ];
        $where = 'created_at >= :date_from::timestamptz AND created_at <= :date_to::timestamptz';
        if ($companyId !== null) {
            $where .= ' AND company_id = :company_id';
            $params['company_id'] = $companyId;
        }

        $stmt = $this->db->pdo()->prepare(
            "SELECT
                count(*) FILTER (WHERE lower(action) LIKE '%login%fail%' OR lower(action) LIKE '%failed_login%')::int AS failed_login,
                count(*) FILTER (WHERE lower(action) LIKE '%organization_mismatch%')::int AS organization_mismatch,
                count(*) FILTER (WHERE lower(action) LIKE '%security%' OR lower(action) LIKE '%tenant_isolation%')::int AS security_events,
                count(*) FILTER (WHERE lower(action) LIKE '%unauthorized%' OR lower(action) LIKE '%forbidden%')::int AS unauthorized_requests,
                count(*) FILTER (WHERE lower(action) LIKE '%device_revok%' OR lower(action) LIKE '%revoke_device%')::int AS device_revocations,
                count(*) FILTER (WHERE lower(action) LIKE '%token%' AND lower(action) LIKE '%valid%')::int AS token_validation_errors,
                count(*) FILTER (WHERE lower(action) LIKE '%jwt%')::int AS jwt_errors
             FROM audit_logs WHERE {$where}",
        );
        $stmt->execute($params);
        $row = $stmt->fetch(PDO::FETCH_ASSOC) ?: [];

        $revokedParams = [
            'date_from' => $dateFrom . ' 00:00:00+00',
            'date_to' => $dateTo . ' 23:59:59+00',
        ];
        $revokedWhere = 'revoked_at IS NOT NULL
            AND revoked_at >= :date_from::timestamptz
            AND revoked_at <= :date_to::timestamptz';
        if ($companyId !== null) {
            $revokedWhere .= ' AND company_id = :company_id';
            $revokedParams['company_id'] = $companyId;
        }
        $revokedStmt = $this->db->pdo()->prepare(
            "SELECT count(*)::int FROM devices WHERE {$revokedWhere}",
        );
        $revokedStmt->execute($revokedParams);
        $revokedDevices = (int) $revokedStmt->fetchColumn();

        return [
            'failed_login' => (int) ($row['failed_login'] ?? 0),
            'organization_mismatch' => (int) ($row['organization_mismatch'] ?? 0),
            'security_events' => (int) ($row['security_events'] ?? 0),
            'unauthorized_requests' => (int) ($row['unauthorized_requests'] ?? 0),
            'device_revocations' => max((int) ($row['device_revocations'] ?? 0), $revokedDevices),
            'token_validation_errors' => (int) ($row['token_validation_errors'] ?? 0),
            'jwt_errors' => (int) ($row['jwt_errors'] ?? 0),
        ];
    }

    /** @return list<array<string, mixed>> */
    private function organizationsTable(?string $companyId): array
    {
        $params = [];
        $where = '1=1';
        if ($companyId !== null) {
            $where = 'c.id = :company_id';
            $params['company_id'] = $companyId;
        }

        $sql = "SELECT
                c.id::text AS organization_id,
                c.name AS organization_name,
                c.status AS company_status,
                cs.status AS subscription_status,
                (
                    SELECT max(sq.processed_at)::text
                    FROM sync_queue sq
                    WHERE sq.company_id = c.id
                ) AS last_sync,
                (
                    SELECT count(*)::int FROM devices d
                    WHERE d.company_id = c.id
                      AND d.revoked_at IS NULL
                      AND d.status = 'active'
                      AND d.last_seen_at >= now() - interval '15 minutes'
                ) AS online_devices,
                (
                    SELECT count(*)::int FROM devices d
                    WHERE d.company_id = c.id
                      AND d.revoked_at IS NULL
                      AND d.status = 'active'
                      AND (d.last_seen_at IS NULL OR d.last_seen_at < now() - interval '15 minutes')
                ) AS offline_devices,
                (
                    SELECT count(*)::int FROM sync_queue sq
                    WHERE sq.company_id = c.id
                      AND sq.status IN ('rejected', 'conflict')
                      AND sq.received_at >= now() - interval '24 hours'
                ) AS failed_sync_count,
                (
                    SELECT count(*)::int FROM sync_queue sq
                    WHERE sq.company_id = c.id AND sq.status = 'pending'
                ) AS pending_outbox,
                (
                    SELECT avg(EXTRACT(EPOCH FROM (sq.processed_at - sq.received_at)))
                    FROM sync_queue sq
                    WHERE sq.company_id = c.id AND sq.processed_at IS NOT NULL
                      AND sq.received_at >= now() - interval '24 hours'
                ) AS average_sync_time_seconds
             FROM companies c
             LEFT JOIN company_subscriptions cs ON cs.company_id = c.id
             WHERE {$where}
             ORDER BY c.name ASC
             LIMIT 200";

        $stmt = $this->db->pdo()->prepare($sql);
        $stmt->execute($params);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC) ?: [];
        $out = [];
        foreach ($rows as $row) {
            $out[] = [
                'organization_id' => (string) ($row['organization_id'] ?? ''),
                'organization_name' => (string) ($row['organization_name'] ?? ''),
                'last_sync' => $row['last_sync'] ?? null,
                'online_devices' => (int) ($row['online_devices'] ?? 0),
                'offline_devices' => (int) ($row['offline_devices'] ?? 0),
                'failed_sync_count' => (int) ($row['failed_sync_count'] ?? 0),
                'pending_outbox' => (int) ($row['pending_outbox'] ?? 0),
                'average_sync_time_seconds' => isset($row['average_sync_time_seconds'])
                    ? round((float) $row['average_sync_time_seconds'], 3)
                    : null,
                'subscription_status' => (string) ($row['subscription_status']
                    ?? $row['company_status']
                    ?? 'unknown'),
            ];
        }

        return $out;
    }

    /** @return array<string, mixed> */
    private function charts(?string $companyId, string $dateFrom, string $dateTo): array
    {
        $params = [
            'date_from' => $dateFrom . ' 00:00:00+00',
            'date_to' => $dateTo . ' 23:59:59+00',
        ];
        $where = 'received_at >= :date_from::timestamptz AND received_at <= :date_to::timestamptz';
        if ($companyId !== null) {
            $where .= ' AND company_id = :company_id';
            $params['company_id'] = $companyId;
        }

        $hourly = $this->db->pdo()->prepare(
            "SELECT to_char(date_trunc('hour', received_at), 'HH24:MI') AS bucket,
                    count(*) FILTER (WHERE status = 'accepted')::int AS success,
                    count(*) FILTER (WHERE status IN ('rejected', 'conflict'))::int AS failure,
                    avg(EXTRACT(EPOCH FROM (processed_at - received_at)))
                        FILTER (WHERE processed_at IS NOT NULL) AS avg_seconds,
                    count(*) FILTER (WHERE status = 'pending')::int AS pending
             FROM sync_queue
             WHERE {$where}
             GROUP BY 1
             ORDER BY 1 ASC
             LIMIT 48",
        );
        $hourly->execute($params);
        $points = [];
        foreach ($hourly->fetchAll(PDO::FETCH_ASSOC) ?: [] as $row) {
            $success = (int) ($row['success'] ?? 0);
            $failure = (int) ($row['failure'] ?? 0);
            $decided = max(1, $success + $failure);
            $points[] = [
                'label' => (string) ($row['bucket'] ?? ''),
                'success' => $success,
                'failure' => $failure,
                'success_rate' => round(($success / $decided) * 100, 1),
                'failure_rate' => round(($failure / $decided) * 100, 1),
                'avg_seconds' => isset($row['avg_seconds']) ? round((float) $row['avg_seconds'], 3) : 0,
                'pending' => (int) ($row['pending'] ?? 0),
            ];
        }

        $onlineOrgs = (int) $this->db->pdo()->query(
            "SELECT count(DISTINCT company_id)::int FROM devices
             WHERE revoked_at IS NULL AND status = 'active'
               AND last_seen_at >= now() - interval '15 minutes'",
        )->fetchColumn();

        return [
            'points' => $points,
            'organizations_online' => $onlineOrgs,
        ];
    }

    /** @return array<string, int> */
    private function devicePresence(): array
    {
        $stmt = $this->db->pdo()->query(
            "SELECT
                count(*) FILTER (
                    WHERE revoked_at IS NULL AND status = 'active'
                      AND last_seen_at >= now() - interval '15 minutes'
                )::int AS online,
                count(*) FILTER (
                    WHERE revoked_at IS NULL AND status = 'active'
                )::int AS active_total,
                count(DISTINCT company_id) FILTER (
                    WHERE revoked_at IS NULL AND status = 'active'
                      AND last_seen_at >= now() - interval '15 minutes'
                )::int AS online_organizations
             FROM devices",
        );
        $row = $stmt->fetch(PDO::FETCH_ASSOC) ?: [];

        return [
            'online' => (int) ($row['online'] ?? 0),
            'active_total' => (int) ($row['active_total'] ?? 0),
            'online_organizations' => (int) ($row['online_organizations'] ?? 0),
        ];
    }

    /**
     * @return array{0:string,1:array<string,string>}
     */
    private function queueFilters(
        ?string $companyId,
        ?string $branchId,
        ?string $deviceId,
        ?string $syncType,
        ?string $status,
    ): array {
        $where = ['1=1'];
        $params = [];
        if ($companyId !== null) {
            $where[] = 'company_id = :company_id';
            $params['company_id'] = $companyId;
        }
        if ($branchId !== null) {
            $where[] = 'branch_id = :branch_id';
            $params['branch_id'] = $branchId;
        }
        if ($deviceId !== null) {
            $where[] = 'device_id = :device_id';
            $params['device_id'] = $deviceId;
        }
        if ($syncType !== null) {
            $where[] = 'entity_type = :sync_type';
            $params['sync_type'] = $syncType;
        }
        if ($status !== null) {
            $where[] = 'status = :status';
            $params['status'] = $status;
        }

        return [implode(' AND ', $where), $params];
    }

    /**
     * @return array{0:string,1:array<string,string>}
     */
    private function changelogFilters(
        ?string $companyId,
        ?string $branchId,
        ?string $deviceId,
        string $dateFrom,
        string $dateTo,
        ?string $syncType,
    ): array {
        $where = [
            'occurred_at >= :date_from::timestamptz',
            'occurred_at <= :date_to::timestamptz',
        ];
        $params = [
            'date_from' => $dateFrom . ' 00:00:00+00',
            'date_to' => $dateTo . ' 23:59:59+00',
        ];
        if ($companyId !== null) {
            $where[] = 'company_id = :company_id';
            $params['company_id'] = $companyId;
        }
        if ($branchId !== null) {
            $where[] = 'branch_id = :branch_id';
            $params['branch_id'] = $branchId;
        }
        if ($deviceId !== null) {
            $where[] = 'origin_device_id = :device_id';
            $params['device_id'] = $deviceId;
        }
        if ($syncType !== null) {
            $where[] = 'entity_type = :sync_type';
            $params['sync_type'] = $syncType;
        }

        return [implode(' AND ', $where), $params];
    }

    private function nonEmpty(mixed $value): ?string
    {
        $v = trim((string) ($value ?? ''));

        return $v !== '' ? $v : null;
    }
}
