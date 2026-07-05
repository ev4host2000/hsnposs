<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Repositories;

use MizaCloud\Core\Database\Repository;
use MizaCloud\Modules\Auth\Support\Uuid;
use PDO;

/**
 * Shared sync_queue / sync_changelog helpers for catalog entity repositories.
 */
abstract class SyncRepositorySupport extends Repository
{
    public function findQueueByIdempotency(string $deviceId, string $idempotencyKey): ?array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT * FROM sync_queue
             WHERE device_id = :device_id AND idempotency_key = :idempotency_key
             LIMIT 1',
        );
        $stmt->execute([
            'device_id' => $deviceId,
            'idempotency_key' => $idempotencyKey,
        ]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
    }

    public function nextSyncSequence(string $companyId): int
    {
        $stmt = $this->db->pdo()->prepare('SELECT miza_next_sync_sequence(:company_id) AS seq');
        $stmt->execute(['company_id' => $companyId]);

        return (int) $stmt->fetchColumn();
    }

    public function bumpCloudVersion(string $companyId, string $branchId, string $entityScope): int
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT miza_bump_cloud_version(:company_id, :branch_id, :entity_scope) AS version',
        );
        $stmt->execute([
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'entity_scope' => $entityScope,
        ]);

        return (int) $stmt->fetchColumn();
    }

    /**
     * @param array<string, mixed> $payloadJson
     */
    public function insertSyncQueue(
        string $companyId,
        string $branchId,
        string $deviceId,
        string $batchId,
        string $entityType,
        string $entityId,
        string $operation,
        array $payloadJson,
        int $clientRowVersion,
        string $idempotencyKey,
    ): string {
        $id = Uuid::v4();
        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO sync_queue (
                id, company_id, branch_id, device_id, batch_id,
                entity_type, entity_id, operation, payload_json,
                client_row_version, status, idempotency_key, processed_at
             ) VALUES (
                :id, :company_id, :branch_id, :device_id, :batch_id,
                :entity_type, :entity_id, :operation, :payload_json::jsonb,
                :client_row_version, \'applied\', :idempotency_key, now()
             )',
        );
        $stmt->execute([
            'id' => $id,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'device_id' => $deviceId,
            'batch_id' => $batchId,
            'entity_type' => $entityType,
            'entity_id' => $entityId,
            'operation' => $operation,
            'payload_json' => json_encode($payloadJson, JSON_THROW_ON_ERROR),
            'client_row_version' => $clientRowVersion,
            'idempotency_key' => $idempotencyKey,
        ]);

        return $id;
    }

    /**
     * @param array<string, mixed> $payloadJson
     */
    public function insertChangelog(
        string $companyId,
        ?string $branchId,
        int $sequence,
        string $entityType,
        string $entityId,
        string $operation,
        array $payloadJson,
        int $rowVersion,
        ?string $originDeviceId,
        ?string $occurredAt,
    ): string {
        $id = Uuid::v4();
        $occurred = $occurredAt ?? gmdate('Y-m-d H:i:s');
        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO sync_changelog (
                id, company_id, branch_id, sequence, entity_type, entity_id,
                operation, payload_json, row_version, origin_device_id, occurred_at
             ) VALUES (
                :id, :company_id, :branch_id, :sequence, :entity_type, :entity_id,
                :operation, :payload_json::jsonb, :row_version, :origin_device_id, :occurred_at
             )',
        );
        $stmt->execute([
            'id' => $id,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'sequence' => $sequence,
            'entity_type' => $entityType,
            'entity_id' => $entityId,
            'operation' => $operation,
            'payload_json' => json_encode($payloadJson, JSON_THROW_ON_ERROR),
            'row_version' => $rowVersion,
            'origin_device_id' => $originDeviceId,
            'occurred_at' => $occurred,
        ]);

        return $id;
    }

    /**
     * @return list<array<string, mixed>>
     */
    public function fetchChangelog(
        string $entityType,
        string $companyId,
        ?string $branchId,
        int $sinceSequence,
        int $limit,
    ): array {
        $sql = 'SELECT sequence, entity_type, entity_id, operation, payload_json,
                       row_version, origin_device_id, occurred_at::text AS occurred_at
                FROM sync_changelog
                WHERE company_id = :company_id
                  AND entity_type = :entity_type
                  AND sequence > :since_sequence';
        $params = [
            'company_id' => $companyId,
            'entity_type' => $entityType,
            'since_sequence' => $sinceSequence,
        ];

        if ($branchId !== null && $branchId !== '') {
            $sql .= ' AND (branch_id = :branch_id OR branch_id IS NULL)';
            $params['branch_id'] = $branchId;
        }

        $sql .= ' ORDER BY sequence ASC LIMIT ' . (int) $limit;

        $stmt = $this->db->pdo()->prepare($sql);
        $stmt->execute($params);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        return is_array($rows) ? $rows : [];
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

    /**
     * @return array<string, mixed>
     */
    protected function softDeleteRow(
        string $table,
        string $companyId,
        string $entityId,
        int $clientRowVersion,
    ): array {
        $stmt = $this->db->pdo()->prepare(
            "UPDATE {$table} SET
                deleted_at = now(),
                row_version = GREATEST(row_version, :client_row_version),
                updated_at = now()
             WHERE id = :id AND company_id = :company_id
             RETURNING row_version",
        );
        $stmt->execute([
            'id' => $entityId,
            'company_id' => $companyId,
            'client_row_version' => $clientRowVersion,
        ]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return [
            'row_version' => is_array($row) ? (int) $row['row_version'] : $clientRowVersion,
            'deleted' => true,
        ];
    }
}
