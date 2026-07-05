<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Repositories;

final class ProductCategoriesSyncRepository extends SyncRepositorySupport
{
    public const ENTITY_TYPE = 'product_category';

    /**
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function applyCategoryLww(
        string $companyId,
        string $branchId,
        string $entityId,
        string $operation,
        array $payload,
        int $clientRowVersion,
        ?string $originDeviceId,
    ): array {
        if ($operation === 'delete') {
            $deleted = $this->softDeleteRow('product_categories', $companyId, $entityId, $clientRowVersion);

            return [
                'id' => $entityId,
                'company_id' => $companyId,
                'branch_id' => $branchId,
                'row_version' => $deleted['row_version'],
                'deleted' => true,
            ];
        }

        $name = trim((string) ($payload['name'] ?? ''));
        $sortOrder = (int) ($payload['sort_order'] ?? 0);

        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO product_categories (
                id, company_id, branch_id, name, sort_order,
                row_version, created_at, updated_at, deleted_at
             ) VALUES (
                :id, :company_id, :branch_id, :name, :sort_order,
                :row_version, now(), now(), NULL
             )
             ON CONFLICT (id) DO UPDATE SET
                name = EXCLUDED.name,
                sort_order = EXCLUDED.sort_order,
                row_version = GREATEST(product_categories.row_version, EXCLUDED.row_version),
                updated_at = now(),
                deleted_at = NULL
             RETURNING row_version, name, sort_order',
        );
        $stmt->execute([
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'name' => $name,
            'sort_order' => $sortOrder,
            'row_version' => max(1, $clientRowVersion),
        ]);
        $row = $stmt->fetch(\PDO::FETCH_ASSOC);
        if (!is_array($row)) {
            throw new \RuntimeException('Product category upsert failed');
        }

        return [
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'name' => (string) $row['name'],
            'sort_order' => (int) $row['sort_order'],
            'row_version' => (int) $row['row_version'],
            'deleted' => false,
        ];
    }
}
