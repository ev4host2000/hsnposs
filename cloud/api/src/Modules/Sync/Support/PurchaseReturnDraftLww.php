<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Support;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Modules\Sync\Repositories\SyncRepositorySupport;
use RuntimeException;

/**
 * Draft-only LWW for purchase returns — header + lines + metadata, no inventory/accounting.
 */
trait PurchaseReturnDraftLww
{
    use PurchaseReturnPostLww;

    /**
     * @param array<string, mixed> $payloadJson
     * @return array<string, mixed>
     */
    protected function applyDraftLww(
        string $companyId,
        string $branchId,
        string $entityId,
        string $operation,
        array $payloadJson,
        int $clientRowVersion,
        ?string $originDeviceId,
    ): array {
        /** @var SyncRepositorySupport $this */
        if ($operation === 'post') {
            return $this->applyPurchaseReturnPost(
                $companyId,
                $branchId,
                $entityId,
                $payloadJson,
                $clientRowVersion,
                $originDeviceId,
            );
        }

        if (in_array($operation, ['cancel', 'delete'], true)) {
            return $this->cancelPurchaseReturnDraft(
                $companyId,
                $branchId,
                $entityId,
                $clientRowVersion,
                $originDeviceId,
            );
        }

        $aggregate = $this->extractAggregate($payloadJson);
        $header = is_array($aggregate['header'] ?? null) ? $aggregate['header'] : [];
        $lines = is_array($aggregate['lines'] ?? null) ? $aggregate['lines'] : [];
        $metadata = is_array($aggregate['metadata'] ?? null) ? $aggregate['metadata'] : [];

        if ((string) ($header['id'] ?? '') !== $entityId) {
            throw new HttpException('validation_error', 'Header id must match entity_id', 400);
        }

        $existing = $this->fetchPurchaseReturnRow($companyId, $entityId);
        // Idempotent create: already on server → success (do not rewrite posted rows).
        if ($operation === 'create' && $existing !== null && ($existing['deleted_at'] ?? null) === null) {
            $status = (string) ($existing['return_status'] ?? 'draft');
            $linesForEnvelope = is_array($lines) ? $lines : [];

            return $this->buildAggregateEnvelope(
                $companyId,
                $branchId,
                $entityId,
                $header,
                $linesForEnvelope,
                $metadata,
                (int) ($existing['row_version'] ?? $clientRowVersion),
                (int) ($existing['transaction_version'] ?? 0),
                $status !== '' ? $status : 'draft',
                $originDeviceId,
            );
        }
        if ($operation === 'update') {
            if ($existing === null || ($existing['deleted_at'] ?? null) !== null) {
                // تحديث لمسودة غير موجودة بعد — عاملها كإنشاء.
                $operation = 'create';
            } elseif (($existing['return_status'] ?? '') !== 'draft') {
                throw new HttpException('return_not_editable', 'Only draft returns can be updated', 409);
            }
        }

        $originalInvoiceId = $this->optionalString($header['original_invoice_id'] ?? null);
        if ($originalInvoiceId === null) {
            throw new HttpException('validation_error', 'original_invoice_id is required', 400);
        }

        $createdBy = $this->optionalString($header['created_by_user_id'] ?? null)
            ?? $this->resolveDefaultUserId($companyId);
        if ($createdBy === null) {
            throw new HttpException('validation_error', 'created_by_user_id is required', 400);
        }

        $supplierId = $this->optionalString($header['supplier_id'] ?? null);
        $returnDate = $this->parseReturnDate($header['return_date'] ?? null);
        $paymentType = trim((string) ($header['payment_type'] ?? 'cash'));
        if ($paymentType === '') {
            $paymentType = 'cash';
        }

        $lineSubtotal = (float) ($header['line_subtotal'] ?? 0);
        $discountAmount = (float) ($header['discount_amount'] ?? 0);
        $taxPercent = (float) ($header['tax_percent'] ?? 0);
        $total = (float) ($header['total'] ?? 0);
        $paidAmount = (float) ($header['paid_amount'] ?? 0);
        $notes = $this->optionalString($header['notes'] ?? null);
        $transactionVersion = max(0, (int) ($header['transaction_version'] ?? 0));
        $rowVersion = max(1, (int) ($header['row_version'] ?? $clientRowVersion));

        $pdo = $this->db->pdo();
        $hasTxnVersion = $this->purchaseReturnHasTransactionVersion();

        if ($hasTxnVersion) {
            $sql = 'INSERT INTO purchase_returns (
                        id, company_id, branch_id, original_invoice_id, supplier_id, return_date,
                        return_status, payment_type, line_subtotal, discount_amount, tax_percent,
                        total, paid_amount, notes, created_by_user_id, origin_device_id,
                        transaction_version, row_version, created_at, updated_at, deleted_at
                    ) VALUES (
                        :id, :company_id, :branch_id, :original_invoice_id, :supplier_id, :return_date,
                        \'draft\', :payment_type, :line_subtotal, :discount_amount, :tax_percent,
                        :total, :paid_amount, :notes, :created_by_user_id, :origin_device_id,
                        :transaction_version, :row_version, now(), now(), NULL
                    )
                    ON CONFLICT (id) DO UPDATE SET
                        original_invoice_id = EXCLUDED.original_invoice_id,
                        supplier_id = EXCLUDED.supplier_id,
                        return_date = EXCLUDED.return_date,
                        return_status = \'draft\',
                        payment_type = EXCLUDED.payment_type,
                        line_subtotal = EXCLUDED.line_subtotal,
                        discount_amount = EXCLUDED.discount_amount,
                        tax_percent = EXCLUDED.tax_percent,
                        total = EXCLUDED.total,
                        paid_amount = EXCLUDED.paid_amount,
                        notes = EXCLUDED.notes,
                        origin_device_id = COALESCE(EXCLUDED.origin_device_id, purchase_returns.origin_device_id),
                        transaction_version = GREATEST(purchase_returns.transaction_version, EXCLUDED.transaction_version),
                        row_version = GREATEST(purchase_returns.row_version, EXCLUDED.row_version),
                        updated_at = now(),
                        deleted_at = NULL
                    RETURNING row_version, transaction_version, return_status';
        } else {
            $sql = 'INSERT INTO purchase_returns (
                        id, company_id, branch_id, original_invoice_id, supplier_id, return_date,
                        return_status, payment_type, line_subtotal, discount_amount, tax_percent,
                        total, paid_amount, notes, created_by_user_id, origin_device_id,
                        row_version, created_at, updated_at, deleted_at
                    ) VALUES (
                        :id, :company_id, :branch_id, :original_invoice_id, :supplier_id, :return_date,
                        \'draft\', :payment_type, :line_subtotal, :discount_amount, :tax_percent,
                        :total, :paid_amount, :notes, :created_by_user_id, :origin_device_id,
                        :row_version, now(), now(), NULL
                    )
                    ON CONFLICT (id) DO UPDATE SET
                        original_invoice_id = EXCLUDED.original_invoice_id,
                        supplier_id = EXCLUDED.supplier_id,
                        return_date = EXCLUDED.return_date,
                        return_status = \'draft\',
                        payment_type = EXCLUDED.payment_type,
                        line_subtotal = EXCLUDED.line_subtotal,
                        discount_amount = EXCLUDED.discount_amount,
                        tax_percent = EXCLUDED.tax_percent,
                        total = EXCLUDED.total,
                        paid_amount = EXCLUDED.paid_amount,
                        notes = EXCLUDED.notes,
                        origin_device_id = COALESCE(EXCLUDED.origin_device_id, purchase_returns.origin_device_id),
                        row_version = GREATEST(purchase_returns.row_version, EXCLUDED.row_version),
                        updated_at = now(),
                        deleted_at = NULL
                    RETURNING row_version, return_status';
        }

        $stmt = $pdo->prepare($sql);
        $params = [
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'original_invoice_id' => $originalInvoiceId,
            'supplier_id' => $supplierId,
            'return_date' => $returnDate,
            'payment_type' => $paymentType,
            'line_subtotal' => $lineSubtotal,
            'discount_amount' => $discountAmount,
            'tax_percent' => $taxPercent,
            'total' => $total,
            'paid_amount' => $paidAmount,
            'notes' => $notes,
            'created_by_user_id' => $createdBy,
            'origin_device_id' => $originDeviceId,
            'row_version' => $rowVersion,
        ];
        if ($hasTxnVersion) {
            $params['transaction_version'] = $transactionVersion;
        }
        $stmt->execute($params);
        $saved = $stmt->fetch(\PDO::FETCH_ASSOC);
        if (!is_array($saved)) {
            throw new RuntimeException('Purchase return upsert failed');
        }

        $this->replacePurchaseReturnLines($pdo, $companyId, $branchId, $entityId, $lines);

        return $this->buildAggregateEnvelope(
            $companyId,
            $branchId,
            $entityId,
            $header,
            $lines,
            $metadata,
            (int) $saved['row_version'],
            (int) ($saved['transaction_version'] ?? $transactionVersion),
            'draft',
            $originDeviceId,
        );
    }

    /**
     * @return array<string, mixed>
     */
    protected function cancelPurchaseReturnDraft(
        string $companyId,
        string $branchId,
        string $entityId,
        int $clientRowVersion,
        ?string $originDeviceId,
    ): array {
        $existing = $this->fetchPurchaseReturnRow($companyId, $entityId);
        if ($existing !== null && ($existing['return_status'] ?? '') !== 'draft') {
            throw new HttpException('return_not_editable', 'Only draft returns can be deleted', 409);
        }

        $deleted = $this->softDeleteRow('purchase_returns', $companyId, $entityId, $clientRowVersion);

        return $this->buildAggregateEnvelope(
            $companyId,
            $branchId,
            $entityId,
            [
                'id' => $entityId,
                'company_id' => $companyId,
                'branch_id' => $branchId,
                'document_type' => 'purchase_return',
                'status' => 'cancelled',
                'transaction_version' => (int) ($existing['transaction_version'] ?? 0),
                'row_version' => (int) $deleted['row_version'],
                'deleted' => true,
            ],
            [],
            ['payload_schema_version' => 1, 'origin_device_id' => $originDeviceId],
            (int) $deleted['row_version'],
            (int) ($existing['transaction_version'] ?? 0),
            'cancelled',
            $originDeviceId,
            deleted: true,
        );
    }

    /**
     * @param array<string, mixed> $payloadJson
     * @return array<string, mixed>
     */
    protected function extractAggregate(array $payloadJson): array
    {
        if (is_array($payloadJson['aggregate'] ?? null)) {
            return $payloadJson['aggregate'];
        }

        if (is_array($payloadJson['header'] ?? null)) {
            return [
                'header' => $payloadJson['header'],
                'lines' => $payloadJson['lines'] ?? [],
                'metadata' => $payloadJson['metadata'] ?? [],
            ];
        }

        throw new HttpException('validation_error', 'Transaction aggregate missing', 400);
    }

    /** @return array<string, mixed>|null */
    protected function fetchPurchaseReturnRow(string $companyId, string $entityId): ?array
    {
        $txnCol = $this->purchaseReturnHasTransactionVersion() ? ', transaction_version' : '';
        $postedCol = $this->purchaseReturnHasPostedAt() ? ', posted_at' : '';
        $stmt = $this->db->pdo()->prepare(
            'SELECT id, return_status, row_version, deleted_at' . $txnCol . $postedCol . '
             FROM purchase_returns
             WHERE id = :id AND company_id = :company_id
             LIMIT 1',
        );
        $stmt->execute(['id' => $entityId, 'company_id' => $companyId]);
        $row = $stmt->fetch(\PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
    }

    /**
     * @param list<array<string, mixed>> $lines
     */
    protected function replacePurchaseReturnLines(
        \PDO $pdo,
        string $companyId,
        string $branchId,
        string $returnId,
        array $lines,
    ): void {
        $delete = $pdo->prepare('DELETE FROM purchase_return_items WHERE return_id = :return_id');
        $delete->execute(['return_id' => $returnId]);

        $insert = $pdo->prepare(
            'INSERT INTO purchase_return_items (
                id, return_id, company_id, branch_id, product_id,
                quantity, unit_cost, line_total, row_version
             ) VALUES (
                :id, :return_id, :company_id, :branch_id, :product_id,
                :quantity, :unit_cost, :line_total, 1
             )',
        );

        foreach ($lines as $line) {
            if (!is_array($line)) {
                continue;
            }
            $lineId = (string) ($line['line_id'] ?? $line['id'] ?? '');
            if ($lineId === '') {
                continue;
            }
            $quantity = (float) ($line['quantity'] ?? 0);
            $unitCost = (float) ($line['unit_cost'] ?? 0);
            $lineTotal = (float) ($line['line_total'] ?? ($quantity * $unitCost));
            $insert->execute([
                'id' => $lineId,
                'return_id' => $returnId,
                'company_id' => $companyId,
                'branch_id' => $branchId,
                'product_id' => (string) ($line['product_id'] ?? ''),
                'quantity' => $quantity,
                'unit_cost' => $unitCost,
                'line_total' => $lineTotal,
            ]);
        }
    }

    /**
     * @param array<string, mixed> $header
     * @param list<array<string, mixed>> $lines
     * @param array<string, mixed> $metadata
     * @return array<string, mixed>
     */
    protected function buildAggregateEnvelope(
        string $companyId,
        string $branchId,
        string $entityId,
        array $header,
        array $lines,
        array $metadata,
        int $rowVersion,
        int $transactionVersion,
        string $status,
        ?string $originDeviceId,
        bool $deleted = false,
    ): array {
        $normalizedHeader = array_merge($header, [
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'document_type' => 'purchase_return',
            'status' => $status,
            'row_version' => $rowVersion,
            'transaction_version' => $transactionVersion,
        ]);
        if ($deleted) {
            $normalizedHeader['deleted'] = true;
        }

        $normalizedMetadata = array_merge(
            ['payload_schema_version' => 1],
            $metadata,
        );
        if ($originDeviceId !== null && $originDeviceId !== '') {
            $normalizedMetadata['origin_device_id'] = $originDeviceId;
        }

        return [
            'aggregate' => [
                'header' => $normalizedHeader,
                'lines' => $lines,
                'metadata' => $normalizedMetadata,
            ],
            'row_version' => $rowVersion,
            'deleted' => $deleted,
        ];
    }

    protected function parseReturnDate(mixed $value): string
    {
        if ($value === null || trim((string) $value) === '') {
            return gmdate('Y-m-d H:i:s');
        }
        $time = strtotime((string) $value);

        return $time === false ? gmdate('Y-m-d H:i:s') : gmdate('Y-m-d H:i:s', $time);
    }

    protected function optionalString(mixed $value): ?string
    {
        if ($value === null) {
            return null;
        }
        $trimmed = trim((string) $value);

        return $trimmed === '' ? null : $trimmed;
    }

    protected function resolveDefaultUserId(string $companyId): ?string
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT id FROM users WHERE company_id = :company_id ORDER BY created_at ASC LIMIT 1',
        );
        $stmt->execute(['company_id' => $companyId]);
        $id = $stmt->fetchColumn();

        return is_string($id) && $id !== '' ? $id : null;
    }

    protected function purchaseReturnHasTransactionVersion(): bool
    {
        static $cached = null;
        if ($cached !== null) {
            return $cached;
        }

        $stmt = $this->db->pdo()->prepare(
            'SELECT 1 FROM information_schema.columns
             WHERE table_schema = current_schema()
               AND table_name = \'purchase_returns\'
               AND column_name = \'transaction_version\'
             LIMIT 1',
        );
        $stmt->execute();
        $cached = (bool) $stmt->fetchColumn();

        return $cached;
    }
}
