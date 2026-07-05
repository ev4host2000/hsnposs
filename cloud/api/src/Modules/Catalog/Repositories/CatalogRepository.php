<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Catalog\Repositories;

use MizaCloud\Core\Database\Repository;
use MizaCloud\Modules\Auth\Support\Uuid;
use MizaCloud\Modules\Catalog\Support\CatalogPartnerSupport;
use MizaCloud\Modules\Catalog\Support\CatalogSalesInvoiceSupport;
use PDO;
use PDOException;

final class CatalogRepository extends Repository
{
    use CatalogPartnerSupport;
    use CatalogSalesInvoiceSupport;
    /**
     * @param array<string, mixed> $filters
     * @return array{items: list<array<string, mixed>>, total_count: int}
     */
    public function listProductCategories(string $companyId, string $branchId, array $filters): array
    {
        return $this->listFromTable(
            'product_categories',
            $companyId,
            $branchId,
            $filters,
            fn (array $row): array => $this->mapCategoryRow($row),
            'sort_order ASC, name ASC',
        );
    }

    /** @return array<string, mixed>|null */
    public function getProductCategory(string $companyId, string $id, bool $includeDeleted = false): ?array
    {
        $row = $this->getRow('product_categories', $companyId, $id, $includeDeleted);

        return $row === null ? null : $this->mapCategoryRow($row);
    }

    /**
     * @param array<string, mixed> $data
     * @return array<string, mixed>
     */
    public function createProductCategory(
        string $companyId,
        string $branchId,
        string $id,
        array $data,
    ): array {
        $name = trim((string) ($data['name'] ?? ''));
        $sortOrder = (int) ($data['sort_order'] ?? 0);

        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO product_categories (
                id, company_id, branch_id, name, sort_order,
                row_version, created_at, updated_at, deleted_at
             ) VALUES (
                :id, :company_id, :branch_id, :name, :sort_order,
                1, now(), now(), NULL
             )
             RETURNING *',
        );
        $stmt->execute([
            'id' => $id,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'name' => $name,
            'sort_order' => $sortOrder,
        ]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!is_array($row)) {
            throw new \RuntimeException('Product category create failed');
        }

        return $this->mapCategoryRow($row);
    }

    /**
     * @param array<string, mixed> $data
     * @return array<string, mixed>
     */
    public function updateProductCategory(string $companyId, string $id, array $data): array
    {
        $fields = [];
        $params = ['id' => $id, 'company_id' => $companyId];

        if (array_key_exists('name', $data)) {
            $fields[] = 'name = :name';
            $params['name'] = trim((string) $data['name']);
        }
        if (array_key_exists('sort_order', $data)) {
            $fields[] = 'sort_order = :sort_order';
            $params['sort_order'] = (int) $data['sort_order'];
        }

        if ($fields === []) {
            $existing = $this->getProductCategory($companyId, $id);
            if ($existing === null) {
                throw new \RuntimeException('Product category not found');
            }

            return $existing;
        }

        $fields[] = 'updated_at = now()';
        $fields[] = 'deleted_at = NULL';

        $stmt = $this->db->pdo()->prepare(
            'UPDATE product_categories SET ' . implode(', ', $fields) . '
             WHERE id = :id AND company_id = :company_id AND deleted_at IS NULL
             RETURNING *',
        );
        $stmt->execute($params);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!is_array($row)) {
            throw new \RuntimeException('Product category update failed');
        }

        return $this->mapCategoryRow($row);
    }

    /** @return array<string, mixed> */
    public function softDeleteProductCategory(string $companyId, string $id): array
    {
        return $this->softDeleteRow('product_categories', $companyId, $id);
    }

    /**
     * @param array<string, mixed> $filters
     * @return array{items: list<array<string, mixed>>, total_count: int}
     */
    public function listProductUnits(string $companyId, string $branchId, array $filters): array
    {
        return $this->listFromTable(
            'product_units',
            $companyId,
            $branchId,
            $filters,
            fn (array $row): array => $this->mapUnitRow($row),
            'name ASC',
        );
    }

    /** @return array<string, mixed>|null */
    public function getProductUnit(string $companyId, string $id, bool $includeDeleted = false): ?array
    {
        $row = $this->getRow('product_units', $companyId, $id, $includeDeleted);

        return $row === null ? null : $this->mapUnitRow($row);
    }

    /**
     * @param array<string, mixed> $data
     * @return array<string, mixed>
     */
    public function createProductUnit(string $companyId, string $branchId, string $id, array $data): array
    {
        $name = trim((string) ($data['name'] ?? ''));

        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO product_units (
                id, company_id, branch_id, name,
                row_version, created_at, updated_at, deleted_at
             ) VALUES (
                :id, :company_id, :branch_id, :name,
                1, now(), now(), NULL
             )
             RETURNING *',
        );
        $stmt->execute([
            'id' => $id,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'name' => $name,
        ]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!is_array($row)) {
            throw new \RuntimeException('Product unit create failed');
        }

        return $this->mapUnitRow($row);
    }

    /**
     * @param array<string, mixed> $data
     * @return array<string, mixed>
     */
    public function updateProductUnit(string $companyId, string $id, array $data): array
    {
        if (!array_key_exists('name', $data)) {
            $existing = $this->getProductUnit($companyId, $id);
            if ($existing === null) {
                throw new \RuntimeException('Product unit not found');
            }

            return $existing;
        }

        $stmt = $this->db->pdo()->prepare(
            'UPDATE product_units SET
                name = :name,
                updated_at = now(),
                deleted_at = NULL
             WHERE id = :id AND company_id = :company_id AND deleted_at IS NULL
             RETURNING *',
        );
        $stmt->execute([
            'id' => $id,
            'company_id' => $companyId,
            'name' => trim((string) $data['name']),
        ]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!is_array($row)) {
            throw new \RuntimeException('Product unit update failed');
        }

        return $this->mapUnitRow($row);
    }

    /** @return array<string, mixed> */
    public function softDeleteProductUnit(string $companyId, string $id): array
    {
        return $this->softDeleteRow('product_units', $companyId, $id);
    }

    /**
     * @param array<string, mixed> $filters
     * @return array{items: list<array<string, mixed>>, total_count: int}
     */
    public function listTaxes(string $companyId, string $branchId, array $filters): array
    {
        return $this->listFromTable(
            'taxes',
            $companyId,
            $branchId,
            $filters,
            fn (array $row): array => $this->mapTaxRow($row),
            'sort_order ASC, name ASC',
        );
    }

    /** @return array<string, mixed>|null */
    public function getTax(string $companyId, string $id, bool $includeDeleted = false): ?array
    {
        $row = $this->getRow('taxes', $companyId, $id, $includeDeleted);

        return $row === null ? null : $this->mapTaxRow($row);
    }

    /**
     * @param array<string, mixed> $data
     * @return array<string, mixed>
     */
    public function createTax(string $companyId, string $branchId, string $id, array $data): array
    {
        $name = trim((string) ($data['name'] ?? ''));
        $percent = (float) ($data['percent'] ?? 0);
        $isDefault = (bool) ($data['is_default'] ?? false);
        $sortOrder = (int) ($data['sort_order'] ?? 0);

        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO taxes (
                id, company_id, branch_id, name, percent, is_default, sort_order,
                row_version, created_at, updated_at, deleted_at
             ) VALUES (
                :id, :company_id, :branch_id, :name, :percent, :is_default, :sort_order,
                1, now(), now(), NULL
             )
             RETURNING *',
        );
        $stmt->execute([
            'id' => $id,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'name' => $name,
            'percent' => $percent,
            'is_default' => $isDefault ? 't' : 'f',
            'sort_order' => $sortOrder,
        ]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!is_array($row)) {
            throw new \RuntimeException('Tax create failed');
        }

        return $this->mapTaxRow($row);
    }

    /**
     * @param array<string, mixed> $data
     * @return array<string, mixed>
     */
    public function updateTax(string $companyId, string $id, array $data): array
    {
        $fields = [];
        $params = ['id' => $id, 'company_id' => $companyId];

        if (array_key_exists('name', $data)) {
            $fields[] = 'name = :name';
            $params['name'] = trim((string) $data['name']);
        }
        if (array_key_exists('percent', $data)) {
            $fields[] = 'percent = :percent';
            $params['percent'] = (float) $data['percent'];
        }
        if (array_key_exists('is_default', $data)) {
            $fields[] = 'is_default = :is_default';
            $params['is_default'] = (bool) $data['is_default'] ? 't' : 'f';
        }
        if (array_key_exists('sort_order', $data)) {
            $fields[] = 'sort_order = :sort_order';
            $params['sort_order'] = (int) $data['sort_order'];
        }

        if ($fields === []) {
            $existing = $this->getTax($companyId, $id);
            if ($existing === null) {
                throw new \RuntimeException('Tax not found');
            }

            return $existing;
        }

        $fields[] = 'updated_at = now()';
        $fields[] = 'deleted_at = NULL';

        $stmt = $this->db->pdo()->prepare(
            'UPDATE taxes SET ' . implode(', ', $fields) . '
             WHERE id = :id AND company_id = :company_id AND deleted_at IS NULL
             RETURNING *',
        );
        $stmt->execute($params);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!is_array($row)) {
            throw new \RuntimeException('Tax update failed');
        }

        return $this->mapTaxRow($row);
    }

    /** @return array<string, mixed> */
    public function softDeleteTax(string $companyId, string $id): array
    {
        return $this->softDeleteRow('taxes', $companyId, $id);
    }

    /**
     * @param array<string, mixed> $filters
     * @return array{items: list<array<string, mixed>>, total_count: int}
     */
    public function listPriceLists(string $companyId, string $branchId, array $filters): array
    {
        return $this->listFromTable(
            'price_lists',
            $companyId,
            $branchId,
            $filters,
            fn (array $row): array => $this->mapPriceListRow($row),
            'sort_order ASC, name ASC',
        );
    }

    /** @return array<string, mixed>|null */
    public function getPriceList(string $companyId, string $id, bool $includeDeleted = false): ?array
    {
        $row = $this->getRow('price_lists', $companyId, $id, $includeDeleted);

        return $row === null ? null : $this->mapPriceListRow($row);
    }

    /**
     * @param array<string, mixed> $data
     * @return array<string, mixed>
     */
    public function createPriceList(string $companyId, string $branchId, string $id, array $data): array
    {
        $name = trim((string) ($data['name'] ?? ''));
        $isDefault = (bool) ($data['is_default'] ?? false);
        $sortOrder = (int) ($data['sort_order'] ?? 0);

        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO price_lists (
                id, company_id, branch_id, name, is_default, sort_order,
                row_version, created_at, updated_at, deleted_at
             ) VALUES (
                :id, :company_id, :branch_id, :name, :is_default, :sort_order,
                1, now(), now(), NULL
             )
             RETURNING *',
        );
        $stmt->execute([
            'id' => $id,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'name' => $name,
            'is_default' => $isDefault ? 't' : 'f',
            'sort_order' => $sortOrder,
        ]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!is_array($row)) {
            throw new \RuntimeException('Price list create failed');
        }

        $items = $this->syncPriceListItems($companyId, $branchId, $id, $data['items'] ?? null);

        return $this->mapPriceListRow($row, $items);
    }

    /**
     * @param array<string, mixed> $data
     * @return array<string, mixed>
     */
    public function updatePriceList(string $companyId, string $branchId, string $id, array $data): array
    {
        $fields = [];
        $params = ['id' => $id, 'company_id' => $companyId];

        if (array_key_exists('name', $data)) {
            $fields[] = 'name = :name';
            $params['name'] = trim((string) $data['name']);
        }
        if (array_key_exists('is_default', $data)) {
            $fields[] = 'is_default = :is_default';
            $params['is_default'] = (bool) $data['is_default'] ? 't' : 'f';
        }
        if (array_key_exists('sort_order', $data)) {
            $fields[] = 'sort_order = :sort_order';
            $params['sort_order'] = (int) $data['sort_order'];
        }

        $row = null;
        if ($fields !== []) {
            $fields[] = 'updated_at = now()';
            $fields[] = 'deleted_at = NULL';

            $stmt = $this->db->pdo()->prepare(
                'UPDATE price_lists SET ' . implode(', ', $fields) . '
                 WHERE id = :id AND company_id = :company_id AND deleted_at IS NULL
                 RETURNING *',
            );
            $stmt->execute($params);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            if (!is_array($row)) {
                throw new \RuntimeException('Price list update failed');
            }
        } else {
            $existing = $this->getPriceList($companyId, $id);
            if ($existing === null) {
                throw new \RuntimeException('Price list not found');
            }
            $row = $existing;
        }

        $items = null;
        if (array_key_exists('items', $data)) {
            $items = $this->syncPriceListItems($companyId, $branchId, $id, $data['items']);
        } else {
            $items = $this->loadActivePriceListItems($companyId, $id);
        }

        return $this->mapPriceListRow(is_array($row) ? $row : [], $items);
    }

    /** @return array<string, mixed> */
    public function softDeletePriceList(string $companyId, string $id): array
    {
        $deleted = $this->softDeleteRow('price_lists', $companyId, $id);
        $this->softDeletePriceListItems($companyId, $id);

        return $deleted;
    }

    public function hasActiveNameConflict(
        string $table,
        string $companyId,
        string $branchId,
        string $name,
        ?string $excludeId = null,
    ): bool {
        $sql = "SELECT 1 FROM {$table}
                WHERE company_id = :company_id
                  AND branch_id = :branch_id
                  AND lower(name) = lower(:name)
                  AND deleted_at IS NULL";
        $params = [
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'name' => $name,
        ];
        if ($excludeId !== null) {
            $sql .= ' AND id <> :exclude_id';
            $params['exclude_id'] = $excludeId;
        }
        $sql .= ' LIMIT 1';

        $stmt = $this->db->pdo()->prepare($sql);
        $stmt->execute($params);

        return (bool) $stmt->fetchColumn();
    }

    public function isUniqueViolation(PDOException $exception): bool
    {
        return $exception->getCode() === '23505'
            || str_contains($exception->getMessage(), 'unique')
            || str_contains($exception->getMessage(), 'duplicate key');
    }

    /**
     * @param array<string, mixed> $filters
     * @param callable(array<string, mixed>): array<string, mixed> $mapRow
     * @return array{items: list<array<string, mixed>>, total_count: int}
     */
    private function listFromTable(
        string $table,
        string $companyId,
        string $branchId,
        array $filters,
        callable $mapRow,
        string $orderBy,
    ): array {
        $includeDeleted = filter_var($filters['include_deleted'] ?? false, FILTER_VALIDATE_BOOLEAN);
        $page = max(1, (int) ($filters['page'] ?? 1));
        $pageSize = min(max((int) ($filters['page_size'] ?? 50), 1), 500);
        $offset = ($page - 1) * $pageSize;

        $where = ['company_id = :company_id', 'branch_id = :branch_id'];
        $params = [
            'company_id' => $companyId,
            'branch_id' => $branchId,
        ];

        if (!$includeDeleted) {
            $where[] = 'deleted_at IS NULL';
        }

        if (!empty($filters['updated_since'])) {
            $where[] = 'updated_at > :updated_since';
            $params['updated_since'] = (string) $filters['updated_since'];
        }

        if (!empty($filters['q'])) {
            $where[] = 'name ILIKE :q';
            $params['q'] = '%' . (string) $filters['q'] . '%';
        }

        $whereSql = implode(' AND ', $where);

        $countStmt = $this->db->pdo()->prepare("SELECT count(*) FROM {$table} WHERE {$whereSql}");
        $countStmt->execute($params);
        $totalCount = (int) $countStmt->fetchColumn();

        $stmt = $this->db->pdo()->prepare(
            "SELECT * FROM {$table}
             WHERE {$whereSql}
             ORDER BY {$orderBy}
             LIMIT :limit OFFSET :offset",
        );
        foreach ($params as $key => $value) {
            $stmt->bindValue(':' . $key, $value);
        }
        $stmt->bindValue(':limit', $pageSize, PDO::PARAM_INT);
        $stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
        $stmt->execute();

        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        $items = [];
        if (is_array($rows)) {
            foreach ($rows as $row) {
                if (is_array($row)) {
                    $items[] = $mapRow($row);
                }
            }
        }

        return [
            'items' => $items,
            'total_count' => $totalCount,
        ];
    }

    /** @return array<string, mixed>|null */
    private function getRow(string $table, string $companyId, string $id, bool $includeDeleted): ?array
    {
        $sql = "SELECT * FROM {$table} WHERE id = :id AND company_id = :company_id";
        if (!$includeDeleted) {
            $sql .= ' AND deleted_at IS NULL';
        }
        $sql .= ' LIMIT 1';

        $stmt = $this->db->pdo()->prepare($sql);
        $stmt->execute([
            'id' => $id,
            'company_id' => $companyId,
        ]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
    }

    /** @return array<string, mixed> */
    private function softDeleteRow(string $table, string $companyId, string $id): array
    {
        $stmt = $this->db->pdo()->prepare(
            "UPDATE {$table} SET
                deleted_at = now(),
                updated_at = now()
             WHERE id = :id AND company_id = :company_id AND deleted_at IS NULL
             RETURNING id, deleted_at::text AS deleted_at, row_version",
        );
        $stmt->execute([
            'id' => $id,
            'company_id' => $companyId,
        ]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!is_array($row)) {
            throw new \RuntimeException('Soft delete failed');
        }

        return [
            'id' => (string) $row['id'],
            'deleted_at' => $this->formatTimestamp((string) $row['deleted_at']),
            'row_version' => (int) $row['row_version'],
        ];
    }

    /** @param array<string, mixed> $row @return array<string, mixed> */
    private function mapCategoryRow(array $row): array
    {
        return [
            'id' => (string) $row['id'],
            'company_id' => (string) $row['company_id'],
            'branch_id' => (string) $row['branch_id'],
            'name' => (string) $row['name'],
            'sort_order' => (int) ($row['sort_order'] ?? 0),
            'row_version' => (int) $row['row_version'],
            'created_at' => $this->formatTimestamp((string) ($row['created_at'] ?? '')),
            'updated_at' => $this->formatTimestamp((string) ($row['updated_at'] ?? '')),
            'deleted_at' => isset($row['deleted_at']) && $row['deleted_at'] !== null
                ? $this->formatTimestamp((string) $row['deleted_at'])
                : null,
        ];
    }

    /** @param array<string, mixed> $row @return array<string, mixed> */
    private function mapUnitRow(array $row): array
    {
        return [
            'id' => (string) $row['id'],
            'company_id' => (string) $row['company_id'],
            'branch_id' => (string) $row['branch_id'],
            'name' => (string) $row['name'],
            'row_version' => (int) $row['row_version'],
            'created_at' => $this->formatTimestamp((string) ($row['created_at'] ?? '')),
            'updated_at' => $this->formatTimestamp((string) ($row['updated_at'] ?? '')),
            'deleted_at' => isset($row['deleted_at']) && $row['deleted_at'] !== null
                ? $this->formatTimestamp((string) $row['deleted_at'])
                : null,
        ];
    }

    /** @param array<string, mixed> $row @return array<string, mixed> */
    private function mapTaxRow(array $row): array
    {
        return [
            'id' => (string) $row['id'],
            'company_id' => (string) $row['company_id'],
            'branch_id' => (string) $row['branch_id'],
            'name' => (string) $row['name'],
            'percent' => (float) $row['percent'],
            'is_default' => filter_var($row['is_default'] ?? false, FILTER_VALIDATE_BOOLEAN),
            'sort_order' => (int) ($row['sort_order'] ?? 0),
            'row_version' => (int) $row['row_version'],
            'created_at' => $this->formatTimestamp((string) ($row['created_at'] ?? '')),
            'updated_at' => $this->formatTimestamp((string) ($row['updated_at'] ?? '')),
            'deleted_at' => isset($row['deleted_at']) && $row['deleted_at'] !== null
                ? $this->formatTimestamp((string) $row['deleted_at'])
                : null,
        ];
    }

    /**
     * @param array<string, mixed> $row
     * @param list<array<string, mixed>>|null $items
     * @return array<string, mixed>
     */
    private function mapPriceListRow(array $row, ?array $items = null): array
    {
        $mapped = [
            'id' => (string) $row['id'],
            'company_id' => (string) $row['company_id'],
            'branch_id' => (string) $row['branch_id'],
            'name' => (string) $row['name'],
            'is_default' => filter_var($row['is_default'] ?? false, FILTER_VALIDATE_BOOLEAN),
            'sort_order' => (int) ($row['sort_order'] ?? 0),
            'row_version' => (int) $row['row_version'],
            'created_at' => $this->formatTimestamp((string) ($row['created_at'] ?? '')),
            'updated_at' => $this->formatTimestamp((string) ($row['updated_at'] ?? '')),
            'deleted_at' => isset($row['deleted_at']) && $row['deleted_at'] !== null
                ? $this->formatTimestamp((string) $row['deleted_at'])
                : null,
        ];

        if ($items !== null) {
            $mapped['items'] = $items;
        }

        return $mapped;
    }

    /**
     * @return list<array<string, mixed>>
     */
    private function syncPriceListItems(
        string $companyId,
        string $branchId,
        string $priceListId,
        mixed $rawItems,
    ): array {
        if (!is_array($rawItems)) {
            return $this->loadActivePriceListItems($companyId, $priceListId);
        }

        $this->softDeletePriceListItems($companyId, $priceListId);
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

    private function softDeletePriceListItems(string $companyId, string $priceListId): void
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

    /** @return list<array<string, mixed>> */
    private function loadActivePriceListItems(string $companyId, string $priceListId): array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT id, product_id, sale_price FROM price_list_items
             WHERE company_id = :company_id AND price_list_id = :price_list_id AND deleted_at IS NULL',
        );
        $stmt->execute([
            'company_id' => $companyId,
            'price_list_id' => $priceListId,
        ]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        if (!is_array($rows)) {
            return [];
        }

        $items = [];
        foreach ($rows as $row) {
            if (!is_array($row)) {
                continue;
            }
            $items[] = [
                'id' => (string) $row['id'],
                'product_id' => (string) $row['product_id'],
                'sale_price' => (float) $row['sale_price'],
            ];
        }

        return $items;
    }

    private function formatTimestamp(string $value): string
    {
        if ($value === '') {
            return $value;
        }
        $time = strtotime($value);

        return $time === false ? $value : gmdate('Y-m-d\TH:i:s.v\Z', $time);
    }
}
