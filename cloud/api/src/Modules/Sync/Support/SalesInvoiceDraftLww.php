<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Support;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Modules\Sync\Repositories\SyncRepositorySupport;
use RuntimeException;

/**
 * Draft-only LWW for sales invoices — header + lines + metadata, no inventory/accounting.
 */
trait SalesInvoiceDraftLww
{
    use SalesInvoicePostLww;

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
            return $this->applySalesInvoicePost(
                $companyId,
                $branchId,
                $entityId,
                $payloadJson,
                $clientRowVersion,
                $originDeviceId,
            );
        }

        if (in_array($operation, ['cancel', 'delete'], true)) {
            return $this->cancelSalesInvoiceDraft(
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

        $existing = $this->fetchSalesInvoiceRow($companyId, $entityId);
        if ($operation === 'create' && $existing !== null && ($existing['deleted_at'] ?? null) === null) {
            throw new HttpException('conflict', 'Invoice already exists', 409);
        }
        if ($operation === 'update') {
            if ($existing === null || ($existing['deleted_at'] ?? null) !== null) {
                throw new HttpException('not_found', 'Draft invoice not found', 404);
            }
            if (($existing['invoice_status'] ?? '') !== 'draft') {
                throw new HttpException('invoice_not_editable', 'Only draft invoices can be updated', 409);
            }
        }

        $createdBy = $this->optionalString($header['created_by_user_id'] ?? null)
            ?? $this->resolveDefaultUserId($companyId);
        if ($createdBy === null) {
            throw new HttpException('validation_error', 'created_by_user_id is required', 400);
        }

        $customerId = $this->optionalString($header['customer_id'] ?? null);
        $invoiceDate = $this->parseInvoiceDate($header['invoice_date'] ?? null);
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
        $hasTxnVersion = $this->salesInvoiceHasTransactionVersion();

        if ($hasTxnVersion) {
            $sql = 'INSERT INTO sales_invoices (
                        id, company_id, branch_id, customer_id, invoice_date, invoice_status,
                        payment_type, line_subtotal, discount_amount, tax_percent, total, paid_amount,
                        notes, created_by_user_id, origin_device_id, transaction_version,
                        row_version, created_at, updated_at, deleted_at
                    ) VALUES (
                        :id, :company_id, :branch_id, :customer_id, :invoice_date, \'draft\',
                        :payment_type, :line_subtotal, :discount_amount, :tax_percent, :total, :paid_amount,
                        :notes, :created_by_user_id, :origin_device_id, :transaction_version,
                        :row_version, now(), now(), NULL
                    )
                    ON CONFLICT (id) DO UPDATE SET
                        customer_id = EXCLUDED.customer_id,
                        invoice_date = EXCLUDED.invoice_date,
                        invoice_status = \'draft\',
                        payment_type = EXCLUDED.payment_type,
                        line_subtotal = EXCLUDED.line_subtotal,
                        discount_amount = EXCLUDED.discount_amount,
                        tax_percent = EXCLUDED.tax_percent,
                        total = EXCLUDED.total,
                        paid_amount = EXCLUDED.paid_amount,
                        notes = EXCLUDED.notes,
                        origin_device_id = COALESCE(EXCLUDED.origin_device_id, sales_invoices.origin_device_id),
                        transaction_version = GREATEST(sales_invoices.transaction_version, EXCLUDED.transaction_version),
                        row_version = GREATEST(sales_invoices.row_version, EXCLUDED.row_version),
                        updated_at = now(),
                        deleted_at = NULL
                    RETURNING row_version, transaction_version, invoice_status';
        } else {
            $sql = 'INSERT INTO sales_invoices (
                        id, company_id, branch_id, customer_id, invoice_date, invoice_status,
                        payment_type, line_subtotal, discount_amount, tax_percent, total, paid_amount,
                        notes, created_by_user_id, origin_device_id,
                        row_version, created_at, updated_at, deleted_at
                    ) VALUES (
                        :id, :company_id, :branch_id, :customer_id, :invoice_date, \'draft\',
                        :payment_type, :line_subtotal, :discount_amount, :tax_percent, :total, :paid_amount,
                        :notes, :created_by_user_id, :origin_device_id,
                        :row_version, now(), now(), NULL
                    )
                    ON CONFLICT (id) DO UPDATE SET
                        customer_id = EXCLUDED.customer_id,
                        invoice_date = EXCLUDED.invoice_date,
                        invoice_status = \'draft\',
                        payment_type = EXCLUDED.payment_type,
                        line_subtotal = EXCLUDED.line_subtotal,
                        discount_amount = EXCLUDED.discount_amount,
                        tax_percent = EXCLUDED.tax_percent,
                        total = EXCLUDED.total,
                        paid_amount = EXCLUDED.paid_amount,
                        notes = EXCLUDED.notes,
                        origin_device_id = COALESCE(EXCLUDED.origin_device_id, sales_invoices.origin_device_id),
                        row_version = GREATEST(sales_invoices.row_version, EXCLUDED.row_version),
                        updated_at = now(),
                        deleted_at = NULL
                    RETURNING row_version, invoice_status';
        }

        $stmt = $pdo->prepare($sql);
        $params = [
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'customer_id' => $customerId,
            'invoice_date' => $invoiceDate,
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
            throw new RuntimeException('Sales invoice upsert failed');
        }

        $this->replaceSalesInvoiceLines($pdo, $companyId, $branchId, $entityId, $lines);

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
    protected function cancelSalesInvoiceDraft(
        string $companyId,
        string $branchId,
        string $entityId,
        int $clientRowVersion,
        ?string $originDeviceId,
    ): array {
        $existing = $this->fetchSalesInvoiceRow($companyId, $entityId);
        if ($existing !== null && ($existing['invoice_status'] ?? '') !== 'draft') {
            throw new HttpException('invoice_not_editable', 'Only draft invoices can be deleted', 409);
        }

        $deleted = $this->softDeleteRow('sales_invoices', $companyId, $entityId, $clientRowVersion);

        return $this->buildAggregateEnvelope(
            $companyId,
            $branchId,
            $entityId,
            [
                'id' => $entityId,
                'company_id' => $companyId,
                'branch_id' => $branchId,
                'document_type' => 'sales_invoice',
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
    protected function fetchSalesInvoiceRow(string $companyId, string $entityId): ?array
    {
        $txnCol = $this->salesInvoiceHasTransactionVersion() ? ', transaction_version' : '';
        $stmt = $this->db->pdo()->prepare(
            'SELECT id, invoice_status, row_version, deleted_at' . $txnCol . '
             FROM sales_invoices
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
    protected function replaceSalesInvoiceLines(
        \PDO $pdo,
        string $companyId,
        string $branchId,
        string $invoiceId,
        array $lines,
    ): void {
        $delete = $pdo->prepare('DELETE FROM sales_invoice_items WHERE invoice_id = :invoice_id');
        $delete->execute(['invoice_id' => $invoiceId]);

        $insert = $pdo->prepare(
            'INSERT INTO sales_invoice_items (
                id, invoice_id, company_id, branch_id, product_id,
                quantity, unit_price, line_total, row_version
             ) VALUES (
                :id, :invoice_id, :company_id, :branch_id, :product_id,
                :quantity, :unit_price, :line_total, 1
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
            $unitPrice = (float) ($line['unit_price'] ?? 0);
            $lineTotal = (float) ($line['line_total'] ?? ($quantity * $unitPrice));
            $insert->execute([
                'id' => $lineId,
                'invoice_id' => $invoiceId,
                'company_id' => $companyId,
                'branch_id' => $branchId,
                'product_id' => (string) ($line['product_id'] ?? ''),
                'quantity' => $quantity,
                'unit_price' => $unitPrice,
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
            'document_type' => 'sales_invoice',
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

    protected function parseInvoiceDate(mixed $value): string
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

    protected function salesInvoiceHasTransactionVersion(): bool
    {
        static $cached = null;
        if ($cached !== null) {
            return $cached;
        }

        $stmt = $this->db->pdo()->prepare(
            'SELECT 1 FROM information_schema.columns
             WHERE table_schema = current_schema()
               AND table_name = \'sales_invoices\'
               AND column_name = \'transaction_version\'
             LIMIT 1',
        );
        $stmt->execute();
        $cached = (bool) $stmt->fetchColumn();

        return $cached;
    }
}
