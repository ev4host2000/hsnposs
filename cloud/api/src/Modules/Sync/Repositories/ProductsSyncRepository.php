<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Repositories;

use MizaCloud\Core\Database\Repository;
use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Modules\Auth\Support\Uuid;
use MizaCloud\Modules\Sync\Support\CatalogVersionGate;
use MizaCloud\Modules\Sync\Support\ProductPatchOrchestrator;
use PDO;

final class ProductsSyncRepository extends Repository
{
    /** @var list<string> */
    private const PATCHABLE_COLUMNS = [
        'name',
        'sale_price',
        'cost_price',
        'barcode',
        'category_id',
        'unit_name',
        'description',
        'image_url',
        'is_hidden',
        'is_frozen',
        'is_service',
        'sort_order',
    ];

    public function __construct(
        \MizaCloud\Core\Database\Connection $db,
        private readonly ProductPatchOrchestrator $patchOrchestrator,
    ) {
        parent::__construct($db);
    }

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
     * @param array<string, mixed> $event
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
        array $event = [],
    ): array {
        $operation = strtolower(trim($operation));
        if ($operation === 'delete') {
            return $this->applyProductDelete(
                $companyId,
                $branchId,
                $entityId,
                $clientRowVersion,
                $originDeviceId,
                $event,
            );
        }

        if ($operation === 'patch') {
            return $this->applyProductPatchUpdate(
                $companyId,
                $branchId,
                $entityId,
                $operation,
                $payload,
                $clientRowVersion,
                $originDeviceId,
                $event,
            );
        }

        if ($operation !== 'create' && $operation !== 'update') {
            $operation = 'update';
        }

        if ($operation === 'create') {
            return $this->applyProductCreate(
                $companyId,
                $branchId,
                $entityId,
                $payload,
                $clientRowVersion,
                $originDeviceId,
            );
        }

        // operation=update: never full-entity overwrite. Existing → Patch path;
        // missing row → create-compatible insert (legacy upsert BC).
        $existing = $this->fetchProductRow($companyId, $entityId);
        if ($existing === null) {
            return $this->applyProductCreate(
                $companyId,
                $branchId,
                $entityId,
                $payload,
                $clientRowVersion,
                $originDeviceId,
            );
        }

        return $this->applyProductPatchUpdate(
            $companyId,
            $branchId,
            $entityId,
            $operation,
            $payload,
            $clientRowVersion,
            $originDeviceId,
            $event,
            $existing,
        );
    }

    /**
     * @param array<string, mixed> $payload
     * @param array<string, mixed> $event
     * @param array<string, mixed>|null $existing
     * @return array<string, mixed>
     */
    private function applyProductPatchUpdate(
        string $companyId,
        string $branchId,
        string $entityId,
        string $operation,
        array $payload,
        int $clientRowVersion,
        ?string $originDeviceId,
        array $event,
        ?array $existing = null,
    ): array {
        $existing ??= $this->fetchProductRow($companyId, $entityId);
        if ($existing === null) {
            throw new HttpException(
                'version_conflict',
                'Product patch rejected: entity not found',
                409,
            );
        }

        try {
            $plan = $this->patchOrchestrator->planUpdate(
                $entityId,
                $operation,
                $event,
                $payload,
                $existing,
                max(1, $clientRowVersion),
            );
        } catch (\InvalidArgumentException $e) {
            throw new HttpException('validation_error', $e->getMessage(), 400);
        }

        if ($plan['decision'] === 'validation_error') {
            throw new HttpException('validation_error', 'Patch validation failed', 400, [
                'fields' => $plan['errors'],
            ]);
        }

        if ($plan['decision'] === CatalogVersionGate::DECISION_CONFLICT) {
            throw new HttpException(
                'version_conflict',
                'Product update rejected: stale or conflicting base_row_version',
                409,
            );
        }

        if ($plan['decision'] === CatalogVersionGate::DECISION_NO_OP) {
            return $this->productEnvelopeFromRow(
                $companyId,
                $branchId,
                $entityId,
                $existing,
                deleted: ($existing['deleted_at'] ?? null) !== null,
                noOp: true,
            );
        }

        $fields = $plan['normalized_changed_fields'];
        if ($fields === []) {
            return $this->productEnvelopeFromRow(
                $companyId,
                $branchId,
                $entityId,
                $existing,
                deleted: false,
                noOp: true,
            );
        }

        if (isset($fields['category_id'])) {
            $fields['category_id'] = $this->sanitizeCategoryId($companyId, $fields['category_id']);
        }

        $row = $this->executeProductPatch(
            $companyId,
            $entityId,
            $fields,
            (int) $plan['new_row_version'],
            $originDeviceId,
            (int) ($existing['row_version'] ?? 1),
        );

        return $this->productEnvelopeFromRow(
            $companyId,
            $branchId,
            $entityId,
            $row,
            deleted: false,
            noOp: false,
        );
    }

    /**
     * Apply only declared patch fields. stock_qty is never written.
     *
     * @param array<string, mixed> $fields
     * @return array<string, mixed>
     */
    private function executeProductPatch(
        string $companyId,
        string $entityId,
        array $fields,
        int $newRowVersion,
        ?string $originDeviceId,
        int $expectedServerVersion,
    ): array {
        $setParts = [];
        $params = [
            'id' => $entityId,
            'company_id' => $companyId,
            'new_row_version' => $newRowVersion,
            'expected_version' => $expectedServerVersion,
            'origin_device_id' => $originDeviceId,
        ];

        foreach ($fields as $name => $value) {
            if (!in_array($name, self::PATCHABLE_COLUMNS, true)) {
                throw new HttpException(
                    'validation_error',
                    'Forbidden or unknown patch column: ' . $name,
                    400,
                );
            }
            $param = 'f_' . $name;
            if (in_array($name, ['is_hidden', 'is_frozen', 'is_service'], true)) {
                $setParts[] = "{$name} = :{$param}";
                $params[$param] = $value ? 't' : 'f';
            } else {
                $setParts[] = "{$name} = :{$param}";
                $params[$param] = $value;
            }
        }

        $setParts[] = 'row_version = :new_row_version';
        $setParts[] = 'origin_device_id = COALESCE(:origin_device_id, products.origin_device_id)';
        $setParts[] = 'updated_at = now()';
        $setParts[] = 'deleted_at = NULL';

        $sql = 'UPDATE products SET ' . implode(', ', $setParts)
            . ' WHERE id = :id AND company_id = :company_id'
            . ' AND row_version = :expected_version'
            . ' RETURNING row_version, branch_id, name, sale_price, cost_price, stock_qty, barcode,'
            . ' category_id, unit_name, description, image_url, is_hidden, is_frozen, is_service, sort_order,'
            . ' deleted_at';

        $stmt = $this->db->pdo()->prepare($sql);
        $stmt->execute($params);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!is_array($row)) {
            throw new HttpException(
                'version_conflict',
                'Product update rejected: concurrent version change',
                409,
            );
        }

        return $row;
    }

    /**
     * Create (full initial payload). Not a catalog patch.
     *
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    private function applyProductCreate(
        string $companyId,
        string $branchId,
        string $entityId,
        array $payload,
        int $clientRowVersion,
        ?string $originDeviceId,
    ): array {
        $existing = $this->fetchProductRow($companyId, $entityId);
        $serverRowVersion = $existing === null ? null : (int) ($existing['row_version'] ?? 1);

        // Create-on-existing: convert to patch against existing (no full overwrite).
        if ($existing !== null) {
            return $this->applyProductPatchUpdate(
                $companyId,
                $branchId,
                $entityId,
                'update',
                $payload,
                $clientRowVersion,
                $originDeviceId,
                [
                    'operation_id' => (string) ($payload['operation_id'] ?? $entityId . ':create'),
                ],
                $existing,
            );
        }

        $decision = CatalogVersionGate::decide(
            CatalogVersionGate::OPERATION_CREATE,
            $serverRowVersion,
            max(1, $clientRowVersion),
            false,
        );

        if ($decision === CatalogVersionGate::DECISION_CONFLICT) {
            throw new HttpException(
                'version_conflict',
                'Product create rejected: stale or conflicting row_version',
                409,
            );
        }

        if ($decision === CatalogVersionGate::DECISION_NO_OP) {
            return $this->productEnvelopeFromRow(
                $companyId,
                $branchId,
                $entityId,
                $existing ?? [],
                deleted: false,
                noOp: true,
            );
        }

        $name = trim((string) ($payload['name'] ?? ''));
        $salePrice = (float) ($payload['sale_price'] ?? 0);
        $costPrice = (float) ($payload['cost_price'] ?? 0);
        $stockQty = (float) ($payload['stock_qty'] ?? 0);
        $barcode = isset($payload['barcode']) ? (string) $payload['barcode'] : null;
        $categoryId = $this->sanitizeCategoryId(
            $companyId,
            isset($payload['category_id']) && $payload['category_id'] !== ''
                ? $payload['category_id']
                : null,
        );
        $unitName = isset($payload['unit_name']) ? (string) $payload['unit_name'] : null;
        $description = isset($payload['description']) ? (string) $payload['description'] : null;
        $imageUrl = null;
        if (array_key_exists('image_url', $payload)) {
            $rawImageUrl = $payload['image_url'];
            $imageUrl = ($rawImageUrl === null || $rawImageUrl === '')
                ? null
                : (string) $rawImageUrl;
        }
        $isHidden = (bool) ($payload['is_hidden'] ?? false);
        $isFrozen = (bool) ($payload['is_frozen'] ?? false);
        $isService = (bool) ($payload['is_service'] ?? false);
        $sortOrder = (int) ($payload['sort_order'] ?? 0);
        $rowVersion = max(1, $clientRowVersion);

        $stmt = $this->db->pdo()->prepare(
            'INSERT INTO products (
                id, company_id, branch_id, name, sale_price, cost_price, stock_qty,
                barcode, category_id, unit_name, description, image_url,
                is_hidden, is_frozen, is_service, is_favorite, sort_order,
                origin_device_id, row_version, created_at, updated_at, deleted_at
             ) VALUES (
                :id, :company_id, :branch_id, :name, :sale_price, :cost_price, :stock_qty,
                :barcode, :category_id, :unit_name, :description, :image_url,
                :is_hidden, :is_frozen, :is_service, false, :sort_order,
                :origin_device_id, :row_version, now(), now(), NULL
             )
             RETURNING row_version, branch_id, name, sale_price, cost_price, stock_qty, barcode,
                       category_id, unit_name, description, image_url, is_hidden, is_frozen, is_service, sort_order,
                       deleted_at',
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
            'image_url' => $imageUrl,
            'is_hidden' => $isHidden ? 't' : 'f',
            'is_frozen' => $isFrozen ? 't' : 'f',
            'is_service' => $isService ? 't' : 'f',
            'sort_order' => $sortOrder,
            'origin_device_id' => $originDeviceId,
            'row_version' => $rowVersion,
        ]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!is_array($row)) {
            throw new HttpException('internal_error', 'Product create failed', 500);
        }

        return $this->productEnvelopeFromRow(
            $companyId,
            $branchId,
            $entityId,
            $row,
            deleted: false,
            noOp: false,
        );
    }

    /**
     * @param array<string, mixed> $event
     * @return array<string, mixed>
     */
    private function applyProductDelete(
        string $companyId,
        string $branchId,
        string $entityId,
        int $clientRowVersion,
        ?string $originDeviceId,
        array $event = [],
    ): array {
        $existing = $this->fetchProductRow($companyId, $entityId);
        $serverRowVersion = $existing === null ? null : (int) ($existing['row_version'] ?? 1);
        $alreadyDeleted = $existing !== null && ($existing['deleted_at'] ?? null) !== null;

        // Prefer base_row_version when provided (Update Contract v2); else client_row_version.
        $versionForGate = $clientRowVersion;
        if (isset($event['base_row_version']) && is_numeric($event['base_row_version'])) {
            $base = (int) $event['base_row_version'];
            if ($base >= 1 && $serverRowVersion !== null && $base !== $serverRowVersion) {
                throw new HttpException(
                    'version_conflict',
                    'Product delete rejected: stale or conflicting base_row_version',
                    409,
                );
            }
            // Gate delete still uses client advancement semantics when base matches.
            $versionForGate = max($clientRowVersion, $base);
        }

        $decision = CatalogVersionGate::decide(
            CatalogVersionGate::OPERATION_DELETE,
            $serverRowVersion,
            max(1, $versionForGate),
            $alreadyDeleted,
        );

        if ($decision === CatalogVersionGate::DECISION_CONFLICT) {
            throw new HttpException(
                'version_conflict',
                'Product delete rejected: stale or conflicting row_version',
                409,
            );
        }

        if ($decision === CatalogVersionGate::DECISION_NO_OP) {
            if ($existing === null) {
                return [
                    'id' => $entityId,
                    'company_id' => $companyId,
                    'branch_id' => $branchId,
                    'row_version' => max(1, $clientRowVersion),
                    'deleted' => true,
                    'no_op' => true,
                ];
            }

            return $this->productEnvelopeFromRow(
                $companyId,
                $branchId,
                $entityId,
                $existing,
                deleted: true,
                noOp: true,
            );
        }

        $clientVersion = max(1, $versionForGate);
        $stmt = $this->db->pdo()->prepare(
            'UPDATE products SET
                deleted_at = now(),
                row_version = :client_row_version,
                updated_at = now()
             WHERE id = :id AND company_id = :company_id
               AND row_version < :client_row_version_guard
             RETURNING row_version, deleted_at IS NOT NULL AS is_deleted',
        );
        $stmt->execute([
            'id' => $entityId,
            'company_id' => $companyId,
            'client_row_version' => $clientVersion,
            'client_row_version_guard' => $clientVersion,
        ]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!is_array($row) && $existing !== null && !$alreadyDeleted
            && (int) ($existing['row_version'] ?? 0) === $clientVersion
        ) {
            $stmtEq = $this->db->pdo()->prepare(
                'UPDATE products SET
                    deleted_at = now(),
                    row_version = :client_row_version,
                    updated_at = now()
                 WHERE id = :id AND company_id = :company_id
                   AND row_version = :client_row_version
                   AND deleted_at IS NULL
                 RETURNING row_version, deleted_at IS NOT NULL AS is_deleted',
            );
            $stmtEq->execute([
                'id' => $entityId,
                'company_id' => $companyId,
                'client_row_version' => $clientVersion,
            ]);
            $row = $stmtEq->fetch(PDO::FETCH_ASSOC);
        }

        if (!is_array($row)) {
            throw new HttpException(
                'version_conflict',
                'Product delete rejected: concurrent version change',
                409,
            );
        }

        return [
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'row_version' => (int) $row['row_version'],
            'deleted' => true,
        ];
    }

    private function sanitizeCategoryId(string $companyId, mixed $categoryId): ?string
    {
        if ($categoryId === null || $categoryId === '') {
            return null;
        }
        $categoryId = (string) $categoryId;
        $catCheck = $this->db->pdo()->prepare(
            'SELECT 1 FROM product_categories
             WHERE id = :id AND company_id = :company_id AND deleted_at IS NULL
             LIMIT 1',
        );
        $catCheck->execute([
            'id' => $categoryId,
            'company_id' => $companyId,
        ]);
        if ($catCheck->fetchColumn() === false) {
            return null;
        }

        return $categoryId;
    }

    /**
     * @return array<string, mixed>|null
     */
    private function fetchProductRow(string $companyId, string $entityId): ?array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT id, company_id, branch_id, name, sale_price, cost_price, stock_qty,
                    barcode, category_id, unit_name, description, image_url,
                    is_hidden, is_frozen, is_service, sort_order, row_version, deleted_at
             FROM products
             WHERE id = :id AND company_id = :company_id
             LIMIT 1',
        );
        $stmt->execute([
            'id' => $entityId,
            'company_id' => $companyId,
        ]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
    }

    /**
     * @param array<string, mixed> $row
     * @return array<string, mixed>
     */
    private function productEnvelopeFromRow(
        string $companyId,
        string $branchId,
        string $entityId,
        array $row,
        bool $deleted,
        bool $noOp,
    ): array {
        if ($deleted) {
            $out = [
                'id' => $entityId,
                'company_id' => $companyId,
                'branch_id' => $branchId,
                'row_version' => (int) ($row['row_version'] ?? 1),
                'deleted' => true,
            ];
            if ($noOp) {
                $out['no_op'] = true;
            }

            return $out;
        }

        $out = [
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => (string) ($row['branch_id'] ?? $branchId),
            'name' => (string) ($row['name'] ?? ''),
            'sale_price' => (float) ($row['sale_price'] ?? 0),
            'cost_price' => (float) ($row['cost_price'] ?? 0),
            'stock_qty' => (float) ($row['stock_qty'] ?? 0),
            'barcode' => $row['barcode'] ?? null,
            'category_id' => $row['category_id'] ?? null,
            'unit_name' => $row['unit_name'] ?? null,
            'description' => $row['description'] ?? null,
            'image_url' => $row['image_url'] ?? null,
            'is_hidden' => (bool) ($row['is_hidden'] ?? false),
            'is_frozen' => (bool) ($row['is_frozen'] ?? false),
            'is_service' => (bool) ($row['is_service'] ?? false),
            'sort_order' => (int) ($row['sort_order'] ?? 0),
            'row_version' => (int) ($row['row_version'] ?? 1),
            'deleted' => false,
        ];
        if ($noOp) {
            $out['no_op'] = true;
        }

        return $out;
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
