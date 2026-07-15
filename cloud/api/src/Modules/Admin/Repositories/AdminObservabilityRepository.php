<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Admin\Repositories;

use MizaCloud\Core\Database\Repository;
use PDO;
use Throwable;

final class AdminObservabilityRepository extends Repository
{
    /** @return list<array<string, mixed>> */
    public function listAuditLogs(
        ?string $companyId,
        ?string $action,
        int $limit = 50,
        int $offset = 0,
    ): array {
        $limit = max(1, min($limit, 200));
        $offset = max(0, $offset);

        $sql = 'SELECT
                al.id::text AS id,
                al.company_id::text AS company_id,
                c.name AS company_name,
                al.branch_id::text AS branch_id,
                al.actor_user_id::text AS actor_user_id,
                al.actor_device_id::text AS actor_device_id,
                al.action,
                al.entity_type,
                al.entity_id::text AS entity_id,
                al.ip_address::text AS ip_address,
                al.created_at::text AS created_at
             FROM audit_logs al
             INNER JOIN companies c ON c.id = al.company_id
             WHERE 1=1';
        $params = [];

        if ($companyId !== null && $companyId !== '') {
            $sql .= ' AND al.company_id = :company_id';
            $params['company_id'] = $companyId;
        }

        if ($action !== null && $action !== '') {
            $sql .= ' AND al.action ILIKE :action';
            $params['action'] = '%' . $action . '%';
        }

        $sql .= ' ORDER BY al.created_at DESC LIMIT :limit OFFSET :offset';

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

    public function countAuditLogs(?string $companyId, ?string $action): int
    {
        $sql = 'SELECT count(*)::int FROM audit_logs al WHERE 1=1';
        $params = [];

        if ($companyId !== null && $companyId !== '') {
            $sql .= ' AND al.company_id = :company_id';
            $params['company_id'] = $companyId;
        }

        if ($action !== null && $action !== '') {
            $sql .= ' AND al.action ILIKE :action';
            $params['action'] = '%' . $action . '%';
        }

        $stmt = $this->db->pdo()->prepare($sql);
        $stmt->execute($params);

        return (int) $stmt->fetchColumn();
    }

    /** @return array<string, mixed> */
    public function platformMetrics(): array
    {
        $stmt = $this->db->pdo()->query(
            'SELECT
                (SELECT count(*)::int FROM companies WHERE status = \'active\') AS active_companies,
                (SELECT count(*)::int FROM companies) AS total_companies,
                (SELECT count(*)::int FROM devices WHERE status = \'active\' AND revoked_at IS NULL) AS active_devices,
                (SELECT count(*)::int FROM users WHERE deleted_at IS NULL) AS total_users,
                (SELECT count(*)::int FROM sync_changelog) AS sync_events_total,
                (SELECT count(*)::int FROM audit_logs) AS audit_events_total',
        );
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : [];
    }

    /** @return list<array<string, mixed>> */
    public function listAlerts(): array
    {
        $alerts = [];

        $expiringStmt = $this->db->pdo()->query(
            'SELECT
                c.id::text AS company_id,
                c.name AS company_name,
                cs.current_period_end::text AS period_end,
                sp.code AS plan_code
             FROM company_subscriptions cs
             INNER JOIN companies c ON c.id = cs.company_id
             INNER JOIN subscription_plans sp ON sp.id = cs.plan_id
             WHERE cs.status IN (\'trial\', \'active\')
               AND cs.current_period_end <= now() + interval \'30 days\'
             ORDER BY cs.current_period_end ASC
             LIMIT 20',
        );
        $expiring = $expiringStmt->fetchAll(PDO::FETCH_ASSOC);
        if (is_array($expiring)) {
            foreach ($expiring as $row) {
                $alerts[] = [
                    'kind' => 'subscription_expiring',
                    'severity' => 'warning',
                    'message' => 'اشتراك ينتهي قريباً: ' . (string) $row['company_name'],
                    'company_id' => (string) $row['company_id'],
                    'company_name' => (string) $row['company_name'],
                    'period_end' => (string) $row['period_end'],
                    'plan_code' => (string) $row['plan_code'],
                ];
            }
        }

        $queuePending = (int) $this->db->pdo()->query(
            'SELECT count(*)::int FROM sync_queue WHERE status = \'pending\'',
        )->fetchColumn();

        if ($queuePending >= 50) {
            $alerts[] = [
                'kind' => 'sync_queue_backlog',
                'severity' => $queuePending >= 200 ? 'critical' : 'warning',
                'message' => "تراكم في طابور المزامنة: {$queuePending} عنصر",
                'count' => $queuePending,
            ];
        }

        $staleDevices = (int) $this->db->pdo()->query(
            'SELECT count(*)::int FROM devices
             WHERE status = \'active\'
               AND revoked_at IS NULL
               AND last_seen_at < now() - interval \'24 hours\'',
        )->fetchColumn();

        if ($staleDevices > 0) {
            $alerts[] = [
                'kind' => 'stale_devices',
                'severity' => 'warning',
                'message' => "أجهزة غائبة (+24 ساعة): {$staleDevices}",
                'count' => $staleDevices,
            ];
        }

        $failedQueue = (int) $this->db->pdo()->query(
            'SELECT count(*)::int FROM sync_queue WHERE status IN (\'rejected\', \'conflict\')',
        )->fetchColumn();

        if ($failedQueue > 0) {
            $alerts[] = [
                'kind' => 'sync_failures',
                'severity' => 'critical',
                'message' => "أخطاء مزامنة غير محلولة: {$failedQueue}",
                'count' => $failedQueue,
            ];
        }

        return $alerts;
    }

    public function countExpiringSubscriptions(int $days = 30): int
    {
        $days = max(1, min($days, 365));
        $stmt = $this->db->pdo()->prepare(
            'SELECT count(*)::int
             FROM company_subscriptions cs
             WHERE cs.status IN (\'trial\', \'active\')
               AND cs.current_period_end <= now() + (:days || \' days\')::interval',
        );
        $stmt->execute(['days' => (string) $days]);

        return (int) $stmt->fetchColumn();
    }

    /** @return array<string, mixed> */
    public function databaseHealth(): array
    {
        $started = microtime(true);

        try {
            $pdo = $this->db->pdo();
            $pdo->query('SELECT 1');
            $version = (string) $pdo->query('SELECT version()')->fetchColumn();
            $dbSize = $pdo->query(
                'SELECT pg_size_pretty(pg_database_size(current_database()))',
            )->fetchColumn();

            return [
                'status' => 'up',
                'connected' => true,
                'latency_ms' => round((microtime(true) - $started) * 1000, 2),
                'version' => $version,
                'database_size' => is_string($dbSize) ? $dbSize : null,
                'error' => null,
            ];
        } catch (Throwable $e) {
            return [
                'status' => 'down',
                'connected' => false,
                'latency_ms' => null,
                'version' => null,
                'database_size' => null,
                'error' => $e->getMessage(),
            ];
        }
    }

    /** @return array<string, mixed> */
    public function storageHealth(string $storageRoot): array
    {
        $paths = [
            'logs' => rtrim($storageRoot, '/\\') . '/logs',
            'media' => rtrim($storageRoot, '/\\') . '/media',
            'rate_limit' => rtrim($storageRoot, '/\\') . '/rate_limit',
        ];

        $disks = [];
        $warnings = [];

        foreach ($paths as $name => $path) {
            $exists = is_dir($path);
            $writable = $exists && is_writable($path);
            $freeBytes = @disk_free_space($path);
            $totalBytes = @disk_total_space($path);

            $freePercent = null;
            if (is_float($freeBytes) && is_float($totalBytes) && $totalBytes > 0) {
                $freePercent = round(($freeBytes / $totalBytes) * 100, 1);
            }

            if ($freePercent !== null && $freePercent < 10) {
                $warnings[] = "مساحة منخفضة في {$name}: {$freePercent}%";
            }

            $disks[$name] = [
                'path' => $path,
                'exists' => $exists,
                'writable' => $writable,
                'free_bytes' => is_float($freeBytes) ? (int) $freeBytes : null,
                'total_bytes' => is_float($totalBytes) ? (int) $totalBytes : null,
                'free_percent' => $freePercent,
            ];
        }

        return [
            'paths' => $disks,
            'warnings' => $warnings,
        ];
    }

    /** @return array<string, mixed> */
    public function logMetrics(string $logPath): array
    {
        $file = rtrim($logPath, '/\\') . '/app.log';
        if (!is_file($file)) {
            return [
                'file' => $file,
                'exists' => false,
                'size_bytes' => 0,
                'recent' => ['debug' => 0, 'info' => 0, 'warning' => 0, 'error' => 0],
            ];
        }

        $sizeBytes = (int) filesize($file);
        $counts = ['debug' => 0, 'info' => 0, 'warning' => 0, 'error' => 0];
        $cutoff = time() - 3600;

        $handle = @fopen($file, 'rb');
        if ($handle === false) {
            return [
                'file' => $file,
                'exists' => true,
                'size_bytes' => $sizeBytes,
                'recent' => $counts,
            ];
        }

        $buffer = '';
        fseek($handle, max(0, $sizeBytes - 65536));
        while (!feof($handle)) {
            $buffer .= (string) fread($handle, 8192);
        }
        fclose($handle);

        foreach (explode("\n", $buffer) as $line) {
            $line = trim($line);
            if ($line === '') {
                continue;
            }
            $decoded = json_decode($line, true);
            if (!is_array($decoded)) {
                continue;
            }
            $time = strtotime((string) ($decoded['time'] ?? ''));
            if ($time !== false && $time < $cutoff) {
                continue;
            }
            $level = (string) ($decoded['level'] ?? '');
            if (isset($counts[$level])) {
                $counts[$level]++;
            }
        }

        return [
            'file' => $file,
            'exists' => true,
            'size_bytes' => $sizeBytes,
            'recent' => $counts,
        ];
    }
}
