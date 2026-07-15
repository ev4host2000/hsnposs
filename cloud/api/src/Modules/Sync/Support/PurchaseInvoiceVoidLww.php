<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Support;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Modules\Auth\Support\Uuid;

/**
 * Void handler for posted purchase invoices — reverse stock + ledger, status=void.
 */
trait PurchaseInvoiceVoidLww
{
    /**
     * @param array<string, mixed> $payloadJson
     * @return array<string, mixed>
     */
    protected function applyPurchaseInvoiceVoid(
        string $companyId,
        string $branchId,
        string $entityId,
        array $payloadJson,
        int $clientRowVersion,
        ?string $originDeviceId,
    ): array {
        /** @var \MizaCloud\Modules\Sync\Repositories\SyncRepositorySupport $this */
        $aggregate = $this->extractAggregate($payloadJson);
        $header = is_array($aggregate['header'] ?? null) ? $aggregate['header'] : [];
        $lines = is_array($aggregate['lines'] ?? null) ? $aggregate['lines'] : [];
        $metadata = is_array($aggregate['metadata'] ?? null) ? $aggregate['metadata'] : [];

        if ((string) ($header['id'] ?? '') !== $entityId) {
            throw new HttpException('validation_error', 'Header id must match entity_id', 400);
        }

        $existing = $this->fetchPurchaseInvoiceRow($companyId, $entityId);
        if ($existing === null || ($existing['deleted_at'] ?? null) !== null) {
            throw new HttpException('not_found', 'Invoice not found', 404);
        }

        $dbStatus = (string) ($existing['invoice_status'] ?? '');
        $dbTxnVersion = (int) ($existing['transaction_version'] ?? 0);
        $headerTxnVersion = max(0, (int) ($header['transaction_version'] ?? 0));

        if ($dbStatus === 'void') {
            if ($headerTxnVersion <= $dbTxnVersion) {
                $cash = $this->extractPostSection($aggregate, $metadata, 'cash');
                if ($cash !== []) {
                    $pdo = $this->db->pdo();
                    $createdBy = $this->optionalString($header['created_by_user_id'] ?? null)
                        ?? $this->resolveDefaultUserId($companyId)
                        ?? 'sync';
                    foreach ($cash as $cashRow) {
                        if (!is_array($cashRow)) {
                            continue;
                        }
                        $cashId = (string) ($cashRow['cash_transaction_id'] ?? $cashRow['id'] ?? '');
                        if ($cashId === '' || !Uuid::isValid($cashId)) {
                            continue;
                        }
                        $type = strtolower(trim((string) ($cashRow['transaction_type'] ?? '')));
                        $amount = (float) ($cashRow['amount'] ?? 0);
                        if (($type !== 'in' && $type !== 'out') || $amount <= 0) {
                            continue;
                        }
                        $this->applyPurchaseVoidCashTransactionIdempotent(
                            $pdo,
                            $companyId,
                            $branchId,
                            $cashId,
                            $type,
                            $amount,
                            (string) ($cashRow['description'] ?? ''),
                            (string) ($cashRow['reference_type'] ?? 'purchase_void'),
                            (string) ($cashRow['reference_id'] ?? $entityId),
                            $this->parseInvoiceDate($cashRow['transaction_date'] ?? null),
                            $createdBy,
                        );
                    }
                }
                return $this->buildPurchaseVoidAggregateEnvelope(
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
            throw new HttpException('already_voided', 'Invoice already voided', 409);
        }

        if ($dbStatus !== 'posted') {
            throw new HttpException(
                'invoice_not_voidable',
                'Only posted invoices can be voided',
                409,
            );
        }

        if ($headerTxnVersion !== $dbTxnVersion + 1 && $headerTxnVersion !== $dbTxnVersion) {
            throw new HttpException(
                'transaction_version_mismatch',
                'Invalid transaction_version for void',
                409,
            );
        }

        $supplierId = $this->optionalString($header['supplier_id'] ?? null);
        if ($supplierId === null || !Uuid::isValid($supplierId)) {
            throw new HttpException('validation_error', 'supplier_id is required for void', 400);
        }

        $createdBy = $this->optionalString($header['created_by_user_id'] ?? null)
            ?? $this->resolveDefaultUserId($companyId);
        if ($createdBy === null) {
            throw new HttpException('validation_error', 'created_by_user_id is required', 400);
        }

        $inventory = $this->extractPostSection($aggregate, $metadata, 'inventory');
        $accounting = $this->extractPostSection($aggregate, $metadata, 'accounting');
        $cash = $this->extractPostSection($aggregate, $metadata, 'cash');
        if ($inventory === []) {
            throw new HttpException('validation_error', 'Void aggregate requires inventory', 400);
        }

        $pdo = $this->db->pdo();
        $voidedAt = gmdate('Y-m-d H:i:s');

        foreach ($inventory as $movement) {
            if (!is_array($movement)) {
                continue;
            }
            $movementId = (string) ($movement['movement_id'] ?? $movement['id'] ?? '');
            if ($movementId === '' || !Uuid::isValid($movementId)) {
                throw new HttpException('validation_error', 'Invalid movement id', 400);
            }
            $this->applyPurchaseVoidStockMovement(
                $pdo,
                $companyId,
                $branchId,
                $movementId,
                (string) ($movement['product_id'] ?? ''),
                (float) ($movement['quantity'] ?? 0),
                (string) ($movement['movement_type'] ?? 'out'),
                (string) ($movement['reference_type'] ?? 'purchase_void'),
                (string) ($movement['reference_id'] ?? $entityId),
                $this->parseInvoiceDate($movement['movement_date'] ?? null),
                $createdBy,
                $originDeviceId,
            );
        }

        foreach ($accounting as $entry) {
            if (!is_array($entry)) {
                continue;
            }
            $entryId = (string) ($entry['entry_id'] ?? $entry['id'] ?? '');
            if ($entryId === '' || !Uuid::isValid($entryId)) {
                throw new HttpException('validation_error', 'Invalid accounting entry id', 400);
            }
            $this->applyPartnerLedgerIdempotent(
                $pdo,
                $companyId,
                $branchId,
                $entryId,
                (string) ($entry['partner_kind'] ?? 'supplier'),
                (string) ($entry['partner_id'] ?? ''),
                (string) ($entry['entry_type'] ?? 'purchase_void'),
                (string) ($entry['reference_type'] ?? 'purchase'),
                (string) ($entry['reference_id'] ?? $entityId),
                (float) ($entry['amount_signed'] ?? 0),
                $this->parseInvoiceDate($entry['entry_date'] ?? null),
                $createdBy,
                $this->optionalString($entry['notes'] ?? null),
            );
        }

        foreach ($cash as $cashRow) {
            if (!is_array($cashRow)) {
                continue;
            }
            $cashId = (string) ($cashRow['cash_transaction_id'] ?? $cashRow['id'] ?? '');
            if ($cashId === '' || !Uuid::isValid($cashId)) {
                throw new HttpException('validation_error', 'Invalid cash transaction id', 400);
            }
            $type = strtolower(trim((string) ($cashRow['transaction_type'] ?? '')));
            if ($type !== 'in' && $type !== 'out') {
                throw new HttpException('validation_error', 'Invalid cash transaction_type', 400);
            }
            $amount = (float) ($cashRow['amount'] ?? 0);
            if ($amount <= 0) {
                continue;
            }
            $this->applyPurchaseVoidCashTransactionIdempotent(
                $pdo,
                $companyId,
                $branchId,
                $cashId,
                $type,
                $amount,
                (string) ($cashRow['description'] ?? ''),
                (string) ($cashRow['reference_type'] ?? 'purchase_void'),
                (string) ($cashRow['reference_id'] ?? $entityId),
                $this->parseInvoiceDate($cashRow['transaction_date'] ?? null),
                $createdBy,
            );
        }

        $nextTxnVersion = $dbTxnVersion + 1;
        $nextRowVersion = max(
            (int) ($existing['row_version'] ?? 1),
            (int) ($header['row_version'] ?? $clientRowVersion),
            $clientRowVersion,
        ) + 1;

        $hasTxnVersion = $this->purchaseInvoiceHasTransactionVersion();
        $setParts = [
            'invoice_status = \'void\'',
            'updated_at = now()',
            'row_version = :row_version',
        ];
        $params = [
            'id' => $entityId,
            'company_id' => $companyId,
            'row_version' => $nextRowVersion,
        ];
        if ($hasTxnVersion) {
            $setParts[] = 'transaction_version = :transaction_version';
            $params['transaction_version'] = $nextTxnVersion;
        }

        $returnCols = $hasTxnVersion
            ? 'row_version, transaction_version, invoice_status'
            : 'row_version, invoice_status';

        $stmt = $pdo->prepare(
            'UPDATE purchase_invoices SET ' . implode(', ', $setParts) . '
             WHERE id = :id AND company_id = :company_id AND invoice_status = \'posted\'
             RETURNING ' . $returnCols,
        );
        $stmt->execute($params);
        $saved = $stmt->fetch(\PDO::FETCH_ASSOC);
        if (!is_array($saved)) {
            $refetched = $this->fetchPurchaseInvoiceRow($companyId, $entityId);
            if ($refetched !== null && (string) ($refetched['invoice_status'] ?? '') === 'void') {
                return $this->buildPurchaseVoidAggregateEnvelope(
                    $companyId,
                    $branchId,
                    $entityId,
                    array_merge($header, [
                        'status' => 'void',
                        'transaction_version' => (int) ($refetched['transaction_version'] ?? $dbTxnVersion),
                        'row_version' => (int) ($refetched['row_version'] ?? $clientRowVersion),
                        'voided_at' => $voidedAt,
                    ]),
                    $lines,
                    $metadata,
                    (int) ($refetched['row_version'] ?? $clientRowVersion),
                    (int) ($refetched['transaction_version'] ?? $dbTxnVersion),
                    $originDeviceId,
                    $aggregate,
                );
            }
            throw new HttpException('voiding_conflict', 'Invoice void conflict — posted lock failed', 409);
        }

        $normalizedHeader = array_merge($header, [
            'status' => 'void',
            'transaction_version' => (int) ($saved['transaction_version'] ?? $nextTxnVersion),
            'row_version' => (int) $saved['row_version'],
            'voided_at' => $voidedAt,
        ]);

        return $this->buildPurchaseVoidAggregateEnvelope(
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

    protected function applyPurchaseVoidStockMovement(
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
        $type = strtolower(trim($movementType));
        if ($type !== 'out') {
            throw new HttpException('validation_error', 'Purchase void stock movement must be out', 400);
        }
        $newStock = $current - $quantity;
        if ($newStock < -1e-9) {
            throw new HttpException('insufficient_stock', 'Insufficient stock for purchase void', 409);
        }

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
            'movement_type' => 'out',
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
    protected function buildPurchaseVoidAggregateEnvelope(
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
        $accounting = $this->extractPostSection($sourceAggregate, $metadata, 'accounting');
        $cash = $this->extractPostSection($sourceAggregate, $metadata, 'cash');

        $normalizedHeader = array_merge($header, [
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'document_type' => 'purchase_invoice',
            'status' => 'void',
            'row_version' => $rowVersion,
            'transaction_version' => $transactionVersion,
        ]);

        $normalizedMetadata = array_merge(
            ['payload_schema_version' => 1],
            $metadata,
            [
                'inventory' => $inventory,
                'accounting' => $accounting,
                'cash' => $cash,
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
                'accounting' => $accounting,
                'cash' => $cash,
                'metadata' => $normalizedMetadata,
            ],
            'row_version' => $rowVersion,
            'deleted' => false,
        ];
    }

    protected function applyPurchaseVoidCashTransactionIdempotent(
        \PDO $pdo,
        string $companyId,
        string $branchId,
        string $transactionId,
        string $transactionType,
        float $amount,
        string $description,
        string $referenceType,
        string $referenceId,
        string $transactionDate,
        string $createdBy,
    ): void {
        $exists = $pdo->prepare('SELECT 1 FROM cash_transactions WHERE id = :id LIMIT 1');
        $exists->execute(['id' => $transactionId]);
        if ($exists->fetchColumn()) {
            return;
        }

        $insert = $pdo->prepare(
            'INSERT INTO cash_transactions (
                id, company_id, branch_id, transaction_type, amount, description,
                reference_type, reference_id, transaction_date, created_by_user_id
             ) VALUES (
                :id, :company_id, :branch_id, :transaction_type, :amount, :description,
                :reference_type, :reference_id, :transaction_date, :created_by_user_id
             )',
        );
        $insert->execute([
            'id' => $transactionId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'transaction_type' => $transactionType,
            'amount' => $amount,
            'description' => $description,
            'reference_type' => $referenceType,
            'reference_id' => $referenceId,
            'transaction_date' => $transactionDate,
            'created_by_user_id' => $createdBy,
        ]);
    }
}
