<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Repositories;

use MizaCloud\Core\Database\Repository;
use MizaCloud\Modules\Auth\Support\Uuid;
use PDO;

final class ProductsSyncRepository extends Repository
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
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function applyProductLww(
        string $companyId,
        string $branchId,
        string $entityId,
        string $operation,
        array $payload,
        int $clientRowVersion,
        ?string $originDeviceId,
    ): array {
        if ($operation === 'delete') {
            $stmt = $this->db->pdo()->prepare(
                'UPDATE products SET
                    deleted_at = now(),
                    row_version = GREATEST(row_version, :client_row_version),
                    updated_at = now()
                 WHERE id = :id AND company_id = :company_id
                 RETURNING row_version, deleted_at IS NOT NULL AS is_deleted',
            );
            $stmt->execute([
                'id' => $entityId,
                'company_id' => $companyId,
                'client_row_version' => $clientRowVersion,
            ]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            if (!is_array($row)) {
                $this->softDeleteInsertStub($companyId, $branchId, $entityId, $clientRowVersion, $originDeviceId);

                return [
                    'id' => $entityId,
                    'company_id' => $companyId,
                    'branch_id' => $branchId,
                    'row_version' => $clientRowVersion,
                    'deleted' => true,
                ];
            }

            return [
                'id' => $entityId,
                'company_id' => $companyId,
                'branch_id' => $branchId,
                'row_version' => (int) $row['row_version'],
                'deleted' => true,
            ];
        }

        $name = trim((string) ($payload['name'] ?? ''));
        $salePrice = (float) ($payload['sale_price'] ?? 0);
        $costPrice = (float) ($payload['cost_price'] ?? 0);
        $stockQty = (float) ($payload['stock_qty'] ?? 0);
        $barcode = isset($payload['barcode']) ? (string) $payload['barcode'] : null;
        $categoryId = isset($payload['category_id']) && $payload['category_id'] !== ''
            ? (string) $payload['category_id']
            : null;
        $unitName = isset($payload['unit_name']) ? (string) $payload['unit_name'] : null;
        $description = isset($payload['description']) ? (string) $payload['description'] : null;
        $isHidden = (bool) ($payload['is_hidden'] ?? false);
        $isFrozen = (bool) ($payload['is_frozen'] ?? false);
        $isService = (bool) ($payload['is_service'] ?? false);
        $sortOrder = (int) ($payload['sort_order'] ?? 0);

        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO products (
                id, company_id, branch_id, name, sale_price, cost_price, stock_qty,
                barcode, category_id, unit_name, description,
                is_hidden, is_frozen, is_service, is_favorite, sort_order,
                origin_device_id, row_version, created_at, updated_at, deleted_at
             ) VALUES (
                :id, :company_id, :branch_id, :name, :sale_price, :cost_price, :stock_qty,
                :barcode, :category_id, :unit_name, :description,
                :is_hidden, :is_frozen, :is_service, false, :sort_order,
                :origin_device_id, :row_version, now(), now(), NULL
             )
             ON CONFLICT (id) DO UPDATE SET
                name = EXCLUDED.name,
                sale_price = EXCLUDED.sale_price,
                cost_price = EXCLUDED.cost_price,
                stock_qty = EXCLUDED.stock_qty,
                barcode = EXCLUDED.barcode,
                category_id = EXCLUDED.category_id,
                unit_name = EXCLUDED.unit_name,
                description = EXCLUDED.description,
                is_hidden = EXCLUDED.is_hidden,
                is_frozen = EXCLUDED.is_frozen,
                is_service = EXCLUDED.is_service,
                sort_order = EXCLUDED.sort_order,
                origin_device_id = COALESCE(EXCLUDED.origin_device_id, products.origin_device_id),
                row_version = GREATEST(products.row_version, EXCLUDED.row_version),
                updated_at = now(),
                deleted_at = NULL
             RETURNING row_version, name, sale_price, cost_price, stock_qty, barcode,
                       category_id, unit_name, description, is_hidden, is_frozen, is_service, sort_order',
        );
        $stmt->execute([
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'name' => $name,
            'sale_price' => $salePrice,
            'cost_price' => $costPrice,
            'stock_qty' => $stockQty,
            'barcode' => $barcode,
            'category_id' => $categoryId,
            'unit_name' => $unitName,
            'description' => $description,
            'is_hidden' => $isHidden ? 't' : 'f',
            'is_frozen' => $isFrozen ? 't' : 'f',
            'is_service' => $isService ? 't' : 'f',
            'sort_order' => $sortOrder,
            'origin_device_id' => $originDeviceId,
            'row_version' => max(1, $clientRowVersion),
        ]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!is_array($row)) {
            throw new \RuntimeException('Product upsert failed');
        }

        return [
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'name' => (string) $row['name'],
            'sale_price' => (float) $row['sale_price'],
            'cost_price' => (float) $row['cost_price'],
            'stock_qty' => (float) $row['stock_qty'],
            'barcode' => $row['barcode'],
            'category_id' => $row['category_id'],
            'unit_name' => $row['unit_name'],
            'description' => $row['description'],
            'is_hidden' => (bool) $row['is_hidden'],
            'is_frozen' => (bool) $row['is_frozen'],
            'is_service' => (bool) $row['is_service'],
            'sort_order' => (int) $row['sort_order'],
            'row_version' => (int) $row['row_version'],
            'deleted' => false,
        ];
    }

    private function softDeleteInsertStub(
        string $companyId,
        string $branchId,
        string $entityId,
        int $clientRowVersion,
        ?string $originDeviceId,
    ): void {
        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO products (
                id, company_id, branch_id, name, origin_device_id,
                row_version, deleted_at, created_at, updated_at
             ) VALUES (
                :id, :company_id, :branch_id, :name, :origin_device_id,
                :row_version, now(), now(), now()
             )
             ON CONFLICT (id) DO UPDATE SET
                deleted_at = now(),
                row_version = GREATEST(products.row_version, EXCLUDED.row_version),
                updated_at = now()',
        );
        $stmt->execute([
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'name' => '(deleted)',
            'origin_device_id' => $originDeviceId,
            'row_version' => max(1, $clientRowVersion),
        ]);
    }

    /**
     * @param array<string, mixed> $payloadJson
     */
    public function insertSyncQueue(
        string $companyId,
        string $branchId,
        string $deviceId,
        string $batchId,
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
                \'product\', :entity_id, :operation, :payload_json::jsonb,
                :client_row_version, \'applied\', :idempotency_key, now()
             )',
        );
        $stmt->execute([
            'id' => $id,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'device_id' => $deviceId,
            'batch_id' => $batchId,
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
                :id, :company_id, :branch_id, :sequence, \'product\', :entity_id,
                :operation, :payload_json::jsonb, :row_version, :origin_device_id, :occurred_at
             )',
        );
        $stmt->execute([
            'id' => $id,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'sequence' => $sequence,
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
    public function fetchProductChangelog(
        string $companyId,
        ?string $branchId,
        int $sinceSequence,
        int $limit,
    ): array {
        $sql = 'SELECT sequence, entity_type, entity_id, operation, payload_json,
                       row_version, origin_device_id, occurred_at::text AS occurred_at
                FROM sync_changelog
                WHERE company_id = :company_id
                  AND entity_type = \'product\'
                  AND sequence > :since_sequence';
        $params = [
            'company_id' => $companyId,
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
}
