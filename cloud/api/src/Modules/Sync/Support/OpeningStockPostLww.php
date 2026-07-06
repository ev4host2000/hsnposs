<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Support;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Modules\Auth\Support\Uuid;

/**
 * Post handler for opening stocks — inventory movements only, no accounting/cash.
 */
trait OpeningStockPostLww
{
    /**
     * @param array<string, mixed> $payloadJson
     * @return array<string, mixed>
     */
    protected function applyOpeningStockPost(
        string $companyId,
        string $branchId,
        string $entityId,
        array $payloadJson,
        int $clientRowVersion,
        ?string $originDeviceId,
    ): array {
        $aggregate = $this->extractAggregate($payloadJson);
        $header = is_array($aggregate['header'] ?? null) ? $aggregate['header'] : [];
        $lines = is_array($aggregate['lines'] ?? null) ? $aggregate['lines'] : [];
        $metadata = is_array($aggregate['metadata'] ?? null) ? $aggregate['metadata'] : [];

        if ((string) ($header['id'] ?? '') !== $entityId) {
            throw new HttpException('validation_error', 'Header id must match entity_id', 400);
        }

        $existing = $this->fetchOpeningStockRow($companyId, $entityId);
        if ($existing === null || ($existing['deleted_at'] ?? null) !== null) {
            throw new HttpException('not_found', 'Draft opening stock not found', 404);
        }

        $dbStatus = (string) ($existing['opening_status'] ?? '');
        $dbTxnVersion = (int) ($existing['transaction_version'] ?? 0);
        $headerTxnVersion = max(0, (int) ($header['transaction_version'] ?? 0));

        if ($dbStatus === 'posted') {
            if ($headerTxnVersion <= $dbTxnVersion) {
                return $this->buildOpeningStockPostAggregateEnvelope(
                    $companyId,
                    $branchId,
                    $entityId,
                    $header,
                    $lines,
                    $metadata,
                    (int) ($existing['row_version'] ?? $clientRowVersion),
                    $dbTxnVersion,
                    $originDeviceId,
                    $aggregate,
                );
            }
            throw new HttpException('already_posted', 'Opening stock already posted', 409);
        }

        if ($dbStatus !== 'draft') {
            throw new HttpException('opening_stock_not_editable', 'Only draft opening stocks can be posted', 409);
        }

        if ($headerTxnVersion !== $dbTxnVersion + 1 && $headerTxnVersion !== $dbTxnVersion) {
            throw new HttpException(
                'transaction_version_mismatch',
                'Invalid transaction_version for post',
                409,
            );
        }

        $productId = $this->optionalString($header['product_id'] ?? null);
        if ($productId === null || !Uuid::isValid($productId)) {
            throw new HttpException('validation_error', 'product_id is required for post', 400);
        }

        $openingQuantity = (float) ($header['opening_quantity'] ?? 0);
        if ($openingQuantity < 1e-9) {
            throw new HttpException('validation_error', 'opening_quantity must be positive for post', 400);
        }

        $createdBy = $this->optionalString($header['created_by_user_id'] ?? null)
            ?? $this->resolveDefaultUserId($companyId);
        if ($createdBy === null) {
            throw new HttpException('validation_error', 'created_by_user_id is required', 400);
        }

        $inventory = $this->extractPostSection($aggregate, $metadata, 'inventory');

        if ($inventory === []) {
            throw new HttpException('validation_error', 'Post aggregate requires inventory', 400);
        }

        $pdo = $this->db->pdo();
        $postedAt = gmdate('Y-m-d H:i:s');

        foreach ($inventory as $movement) {
            if (!is_array($movement)) {
                continue;
            }
            $movementId = (string) ($movement['movement_id'] ?? $movement['id'] ?? '');
            if ($movementId === '' || !Uuid::isValid($movementId)) {
                throw new HttpException('validation_error', 'Invalid movement id', 400);
            }
            $movementQty = abs((float) ($movement['quantity'] ?? $openingQuantity));
            $movementType = trim((string) ($movement['movement_type'] ?? ''));
            if ($movementType === '') {
                $movementType = $openingQuantity > 0 ? 'in' : 'out';
            }
            $this->applyStockMovementIdempotent(
                $pdo,
                $companyId,
                $branchId,
                $movementId,
                (string) ($movement['product_id'] ?? $productId),
                $movementQty,
                $movementType,
                (string) ($movement['reference_type'] ?? 'opening_stock'),
                (string) ($movement['reference_id'] ?? $entityId),
                $this->parseOpeningDate($movement['movement_date'] ?? null),
                $createdBy,
                $originDeviceId,
            );
        }

        $nextTxnVersion = $dbTxnVersion + 1;
        $nextRowVersion = max(
            (int) ($existing['row_version'] ?? 1),
            (int) ($header['row_version'] ?? $clientRowVersion),
            $clientRowVersion,
        ) + 1;

        $hasPostedAt = $this->openingStockHasPostedAt();
        $hasTxnVersion = $this->openingStockHasTransactionVersion();

        $setParts = [
            'opening_status = \'posted\'',
            'updated_at = now()',
            'row_version = :row_version',
        ];
        $params = [
            'id' => $entityId,
            'company_id' => $companyId,
            'row_version' => $nextRowVersion,
        ];
        if ($hasPostedAt) {
            $setParts[] = 'posted_at = :posted_at';
            $params['posted_at'] = $postedAt;
        }
        if ($hasTxnVersion) {
            $setParts[] = 'transaction_version = :transaction_version';
            $params['transaction_version'] = $nextTxnVersion;
        }

        $returnCols = 'row_version, opening_status';
        if ($hasTxnVersion) {
            $returnCols = 'row_version, transaction_version, opening_status';
        }

        $stmt = $pdo->prepare(
            'UPDATE opening_stocks SET ' . implode(', ', $setParts) . '
             WHERE id = :id AND company_id = :company_id AND opening_status = \'draft\'
             RETURNING ' . $returnCols,
        );
        $stmt->execute($params);
        $saved = $stmt->fetch(\PDO::FETCH_ASSOC);
        if (!is_array($saved)) {
            $refetched = $this->fetchOpeningStockRow($companyId, $entityId);
            if ($refetched !== null && (string) ($refetched['opening_status'] ?? '') === 'posted') {
                return $this->buildOpeningStockPostAggregateEnvelope(
                    $companyId,
                    $branchId,
                    $entityId,
                    array_merge($header, [
                        'status' => 'posted',
                        'transaction_version' => (int) ($refetched['transaction_version'] ?? $dbTxnVersion),
                        'row_version' => (int) ($refetched['row_version'] ?? $clientRowVersion),
                        'posted_at' => $refetched['posted_at'] ?? $postedAt,
                    ]),
                    $lines,
                    $metadata,
                    (int) ($refetched['row_version'] ?? $clientRowVersion),
                    (int) ($refetched['transaction_version'] ?? $dbTxnVersion),
                    $originDeviceId,
                    $aggregate,
                );
            }
            throw new HttpException('posting_conflict', 'Opening stock post conflict — draft lock failed', 409);
        }

        $normalizedHeader = array_merge($header, [
            'status' => 'posted',
            'transaction_version' => (int) ($saved['transaction_version'] ?? $nextTxnVersion),
            'row_version' => (int) $saved['row_version'],
            'posted_at' => $postedAt,
        ]);

        return $this->buildOpeningStockPostAggregateEnvelope(
            $companyId,
            $branchId,
            $entityId,
            $normalizedHeader,
            $lines,
            $metadata,
            (int) $saved['row_version'],
            (int) ($saved['transaction_version'] ?? $nextTxnVersion),
            $originDeviceId,
            $aggregate,
        );
    }

    /**
     * @param array<string, mixed> $aggregate
     * @param array<string, mixed> $metadata
     * @return list<array<string, mixed>>
     */
    protected function extractPostSection(array $aggregate, array $metadata, string $key): array
    {
        if (is_array($aggregate[$key] ?? null)) {
            return array_values(array_filter($aggregate[$key], 'is_array'));
        }
        if (is_array($metadata[$key] ?? null)) {
            return array_values(array_filter($metadata[$key], 'is_array'));
        }

        return [];
    }

    protected function applyStockMovementIdempotent(
        \PDO $pdo,
        string $companyId,
        string $branchId,
        string $movementId,
        string $productId,
        float $quantity,
        string $movementType,
        string $referenceType,
        string $referenceId,
        string $movementDate,
        string $createdBy,
        ?string $originDeviceId,
    ): void {
        $exists = $pdo->prepare('SELECT 1 FROM stock_movements WHERE id = :id LIMIT 1');
        $exists->execute(['id' => $movementId]);
        if ($exists->fetchColumn()) {
            return;
        }

        $product = $pdo->prepare(
            'SELECT stock_qty FROM products
             WHERE id = :id AND company_id = :company_id LIMIT 1',
        );
        $product->execute(['id' => $productId, 'company_id' => $companyId]);
        $stockRow = $product->fetch(\PDO::FETCH_ASSOC);
        if (!is_array($stockRow)) {
            throw new HttpException('product_not_found', 'Product not found for stock movement', 404);
        }

        $current = (float) ($stockRow['stock_qty'] ?? 0);
        $newStock = $current + $quantity;

        $insert = $pdo->prepare(
            'INSERT INTO stock_movements (
                id, company_id, branch_id, product_id, movement_type, quantity,
                reference_type, reference_id, movement_date, created_by_user_id, origin_device_id
             ) VALUES (
                :id, :company_id, :branch_id, :product_id, :movement_type, :quantity,
                :reference_type, :reference_id, :movement_date, :created_by_user_id, :origin_device_id
             )',
        );
        $insert->execute([
            'id' => $movementId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'product_id' => $productId,
            'movement_type' => $movementType,
            'quantity' => $quantity,
            'reference_type' => $referenceType,
            'reference_id' => $referenceId,
            'movement_date' => $movementDate,
            'created_by_user_id' => $createdBy,
            'origin_device_id' => $originDeviceId,
        ]);

        $update = $pdo->prepare(
            'UPDATE products SET stock_qty = :stock_qty, updated_at = now()
             WHERE id = :id AND company_id = :company_id',
        );
        $update->execute([
            'stock_qty' => $newStock,
            'id' => $productId,
            'company_id' => $companyId,
        ]);
    }

    /**
     * @param array<string, mixed> $header
     * @param list<array<string, mixed>> $lines
     * @param array<string, mixed> $metadata
     * @param array<string, mixed> $sourceAggregate
     * @return array<string, mixed>
     */
    protected function buildOpeningStockPostAggregateEnvelope(
        string $companyId,
        string $branchId,
        string $entityId,
        array $header,
        array $lines,
        array $metadata,
        int $rowVersion,
        int $transactionVersion,
        ?string $originDeviceId,
        array $sourceAggregate,
    ): array {
        $inventory = $this->extractPostSection($sourceAggregate, $metadata, 'inventory');

        $normalizedHeader = array_merge($header, [
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'document_type' => 'opening_stock',
            'status' => 'posted',
            'row_version' => $rowVersion,
            'transaction_version' => $transactionVersion,
        ]);

        $normalizedMetadata = array_merge(
            ['payload_schema_version' => 1],
            $metadata,
            [
                'inventory' => $inventory,
            ],
        );
        if ($originDeviceId !== null && $originDeviceId !== '') {
            $normalizedMetadata['origin_device_id'] = $originDeviceId;
        }

        return [
            'aggregate' => [
                'header' => $normalizedHeader,
                'lines' => $lines,
                'inventory' => $inventory,
                'metadata' => $normalizedMetadata,
            ],
            'row_version' => $rowVersion,
            'deleted' => false,
        ];
    }

    protected function openingStockHasPostedAt(): bool
    {
        static $cached = null;
        if ($cached !== null) {
            return $cached;
        }

        $stmt = $this->db->pdo()->prepare(
            'SELECT 1 FROM information_schema.columns
             WHERE table_schema = current_schema()
               AND table_name = \'opening_stocks\'
               AND column_name = \'posted_at\'
             LIMIT 1',
        );
        $stmt->execute();
        $cached = (bool) $stmt->fetchColumn();

        return $cached;
    }

    protected function openingStockHasTransactionVersion(): bool
    {
        static $cached = null;
        if ($cached !== null) {
            return $cached;
        }

        $stmt = $this->db->pdo()->prepare(
            'SELECT 1 FROM information_schema.columns
             WHERE table_schema = current_schema()
               AND table_name = \'opening_stocks\'
               AND column_name = \'transaction_version\'
             LIMIT 1',
        );
        $stmt->execute();
        $cached = (bool) $stmt->fetchColumn();

        return $cached;
    }
}
