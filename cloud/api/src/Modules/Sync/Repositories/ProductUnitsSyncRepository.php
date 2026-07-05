<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Repositories;

final class ProductUnitsSyncRepository extends SyncRepositorySupport
{
    public const ENTITY_TYPE = 'product_unit';

    /**
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function applyUnitLww(
        string $companyId,
        string $branchId,
        string $entityId,
        string $operation,
        array $payload,
        int $clientRowVersion,
        ?string $originDeviceId,
    ): array {
        if ($operation === 'delete') {
            $deleted = $this->softDeleteRow('product_units', $companyId, $entityId, $clientRowVersion);

            return [
                'id' => $entityId,
                'company_id' => $companyId,
                'branch_id' => $branchId,
                'row_version' => $deleted['row_version'],
                'deleted' => true,
            ];
        }

        $name = trim((string) ($payload['name'] ?? ''));

        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO product_units (
                id, company_id, branch_id, name,
                row_version, created_at, updated_at, deleted_at
             ) VALUES (
                :id, :company_id, :branch_id, :name,
                :row_version, now(), now(), NULL
             )
             ON CONFLICT (id) DO UPDATE SET
                name = EXCLUDED.name,
                row_version = GREATEST(product_units.row_version, EXCLUDED.row_version),
                updated_at = now(),
                deleted_at = NULL
             RETURNING row_version, name',
        );
        $stmt->execute([
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'name' => $name,
            'row_version' => max(1, $clientRowVersion),
        ]);
        $row = $stmt->fetch(\PDO::FETCH_ASSOC);
        if (!is_array($row)) {
            throw new \RuntimeException('Product unit upsert failed');
        }

        return [
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'name' => (string) $row['name'],
            'row_version' => (int) $row['row_version'],
            'deleted' => false,
        ];
    }
}
