<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Repositories;

use MizaCloud\Modules\Auth\Support\Uuid;

final class PriceListsSyncRepository extends SyncRepositorySupport
{
    public const ENTITY_TYPE = 'price_list';

    /**
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function applyPriceListLww(
        string $companyId,
        string $branchId,
        string $entityId,
        string $operation,
        array $payload,
        int $clientRowVersion,
        ?string $originDeviceId,
    ): array {
        if ($operation === 'delete') {
            $deleted = $this->softDeleteRow('price_lists', $companyId, $entityId, $clientRowVersion);
            $this->softDeleteItems($companyId, $entityId);

            return [
                'id' => $entityId,
                'company_id' => $companyId,
                'branch_id' => $branchId,
                'row_version' => $deleted['row_version'],
                'deleted' => true,
            ];
        }

        $name = trim((string) ($payload['name'] ?? ''));
        $isDefault = (bool) ($payload['is_default'] ?? false);
        $sortOrder = (int) ($payload['sort_order'] ?? 0);

        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO price_lists (
                id, company_id, branch_id, name, is_default, sort_order,
                row_version, created_at, updated_at, deleted_at
             ) VALUES (
                :id, :company_id, :branch_id, :name, :is_default, :sort_order,
                :row_version, now(), now(), NULL
             )
             ON CONFLICT (id) DO UPDATE SET
                name = EXCLUDED.name,
                is_default = EXCLUDED.is_default,
                sort_order = EXCLUDED.sort_order,
                row_version = GREATEST(price_lists.row_version, EXCLUDED.row_version),
                updated_at = now(),
                deleted_at = NULL
             RETURNING row_version, name, is_default, sort_order',
        );
        $stmt->execute([
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'name' => $name,
            'is_default' => $isDefault ? 't' : 'f',
            'sort_order' => $sortOrder,
            'row_version' => max(1, $clientRowVersion),
        ]);
        $row = $stmt->fetch(\PDO::FETCH_ASSOC);
        if (!is_array($row)) {
            throw new \RuntimeException('Price list upsert failed');
        }

        $items = $this->syncItems($companyId, $branchId, $entityId, $payload['items'] ?? []);

        return [
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'name' => (string) $row['name'],
            'is_default' => (bool) $row['is_default'],
            'sort_order' => (int) $row['sort_order'],
            'items' => $items,
            'row_version' => (int) $row['row_version'],
            'deleted' => false,
        ];
    }

    private function softDeleteItems(string $companyId, string $priceListId): void
    {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE price_list_items SET deleted_at = now(), updated_at = now()
             WHERE company_id = :company_id AND price_list_id = :price_list_id AND deleted_at IS NULL',
        );
        $stmt->execute([
            'company_id' => $companyId,
            'price_list_id' => $priceListId,
        ]);
    }

    /**
     * @return list<array<string, mixed>>
     */
    private function syncItems(
        string $companyId,
        string $branchId,
        string $priceListId,
        mixed $rawItems,
    ): array {
        if (!is_array($rawItems)) {
            return $this->loadActiveItems($companyId, $priceListId);
        }

        $this->softDeleteItems($companyId, $priceListId);
        $result = [];

        foreach ($rawItems as $item) {
            if (!is_array($item)) {
                continue;
            }
            $productId = (string) ($item['product_id'] ?? '');
            if ($productId === '' || !Uuid::isValid($productId)) {
                continue;
            }
            $salePrice = (float) ($item['sale_price'] ?? 0);
            $itemId = isset($item['id']) && Uuid::isValid((string) $item['id'])
                ? (string) $item['id']
                : Uuid::v4();

            $stmt = $this->db->pdo()->prepare(
                'INSERT INTO price_list_items (
                    id, company_id, branch_id, price_list_id, product_id, sale_price,
                    row_version, created_at, updated_at, deleted_at
                 ) VALUES (
                    :id, :company_id, :branch_id, :price_list_id, :product_id, :sale_price,
                    1, now(), now(), NULL
                 )
                 ON CONFLICT (id) DO UPDATE SET
                    product_id = EXCLUDED.product_id,
                    sale_price = EXCLUDED.sale_price,
                    deleted_at = NULL,
                    updated_at = now(),
                    row_version = price_list_items.row_version + 1',
            );
            $stmt->execute([
                'id' => $itemId,
                'company_id' => $companyId,
                'branch_id' => $branchId,
                'price_list_id' => $priceListId,
                'product_id' => $productId,
                'sale_price' => $salePrice,
            ]);

            $result[] = [
                'id' => $itemId,
                'product_id' => $productId,
                'sale_price' => $salePrice,
            ];
        }

        return $result;
    }

    /**
     * @return list<array<string, mixed>>
     */
    private function loadActiveItems(string $companyId, string $priceListId): array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT id, product_id, sale_price FROM price_list_items
             WHERE company_id = :company_id AND price_list_id = :price_list_id AND deleted_at IS NULL',
        );
        $stmt->execute([
            'company_id' => $companyId,
            'price_list_id' => $priceListId,
        ]);
        $rows = $stmt->fetchAll(\PDO::FETCH_ASSOC);
        if (!is_array($rows)) {
            return [];
        }

        $items = [];
        foreach ($rows as $row) {
            $items[] = [
                'id' => (string) $row['id'],
                'product_id' => (string) $row['product_id'],
                'sale_price' => (float) $row['sale_price'],
            ];
        }

        return $items;
    }
}
