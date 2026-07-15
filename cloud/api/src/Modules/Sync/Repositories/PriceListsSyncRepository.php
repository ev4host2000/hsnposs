<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Repositories;

use MizaCloud\Modules\Auth\Support\Uuid;
use MizaCloud\Modules\Sync\Contract\PatchValidator;
use MizaCloud\Modules\Sync\Support\CatalogPatchOrchestrator;
use MizaCloud\Modules\Sync\Support\NamedEntityLww;

/**
 * Price lists: header via NamedEntityLww (Golden Reference).
 * Nested items are price-list nature — synced outside Field Dictionary.
 */
final class PriceListsSyncRepository extends SyncRepositorySupport
{
    use NamedEntityLww;

    public const ENTITY_TYPE = 'price_list';

    public function __construct(
        \MizaCloud\Core\Database\Connection $db,
        private readonly CatalogPatchOrchestrator $patchOrchestrator,
    ) {
        parent::__construct($db);
    }

    protected function namedPatchOrchestrator(): CatalogPatchOrchestrator
    {
        return $this->patchOrchestrator;
    }

    protected function namedEntityType(): string
    {
        return self::ENTITY_TYPE;
    }

    protected function namedEntityPath(): string
    {
        return PatchValidator::PATH_PRICE_LIST_CATALOG_PATCH;
    }

    protected function namedTable(): string
    {
        return 'price_lists';
    }

    /** @return list<string> */
    protected function namedPatchableColumns(): array
    {
        return ['name', 'is_default', 'sort_order'];
    }

    /**
     * @param array<string, mixed> $payload
     * @param array<string, mixed> $event
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
        array $event = [],
    ): array {
        $operation = strtolower(trim($operation));

        $result = $this->applyNamedEntityLww(
            $companyId,
            $branchId,
            $entityId,
            $operation,
            $payload,
            $clientRowVersion,
            $originDeviceId,
            $event,
        );

        if ($operation === 'delete') {
            // Price-list nature: items belong to the list header.
            $this->softDeleteItems($companyId, $entityId);

            return $result;
        }

        $hasItemsKey = array_key_exists('items', $payload);
        if ($operation === 'create' || $hasItemsKey) {
            $beforeItems = $this->loadActiveItems($companyId, $entityId);
            $items = $this->syncItems($companyId, $branchId, $entityId, $payload['items'] ?? []);
            $result['items'] = $items;

            // Header no_op must not hide item mutations (Full payload always carries items).
            if (($result['no_op'] ?? false) === true
                && $hasItemsKey
                && !$this->itemsSemanticallyEqual($beforeItems, $this->normalizeItemsForCompare($payload['items'] ?? []))
            ) {
                $result['row_version'] = $this->bumpPriceListRowVersion($companyId, $entityId);
                $result['no_op'] = false;
            }
        } else {
            $result['items'] = $this->loadActiveItems($companyId, $entityId);
        }

        return $result;
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

    private function bumpPriceListRowVersion(string $companyId, string $entityId): int
    {
        $stmt = $this->db->pdo()->prepare(
            'UPDATE price_lists
             SET row_version = row_version + 1, updated_at = now()
             WHERE id = :id AND company_id = :company_id
             RETURNING row_version',
        );
        $stmt->execute([
            'id' => $entityId,
            'company_id' => $companyId,
        ]);
        $version = $stmt->fetchColumn();

        return max(1, (int) $version);
    }

    /**
     * @param list<array<string, mixed>> $a
     * @param list<array<string, mixed>> $b
     */
    private function itemsSemanticallyEqual(array $a, array $b): bool
    {
        $norm = static function (array $items): array {
            $out = [];
            foreach ($items as $item) {
                $productId = (string) ($item['product_id'] ?? '');
                if ($productId === '') {
                    continue;
                }
                $out[$productId] = round((float) ($item['sale_price'] ?? 0), 4);
            }
            ksort($out);

            return $out;
        };

        return $norm($a) === $norm($b);
    }

    /**
     * @return list<array<string, mixed>>
     */
    private function normalizeItemsForCompare(mixed $rawItems): array
    {
        if (!is_array($rawItems)) {
            return [];
        }
        $out = [];
        foreach ($rawItems as $item) {
            if (!is_array($item)) {
                continue;
            }
            $productId = (string) ($item['product_id'] ?? '');
            if ($productId === '') {
                continue;
            }
            $out[] = [
                'product_id' => $productId,
                'sale_price' => (float) ($item['sale_price'] ?? 0),
            ];
        }

        return $out;
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
