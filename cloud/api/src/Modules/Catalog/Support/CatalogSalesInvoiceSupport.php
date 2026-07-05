<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Catalog\Support;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Modules\Auth\Support\Uuid;
use PDO;
use RuntimeException;

/**
 * REST CRUD for draft sales invoices — no post/inventory/accounting.
 */
trait CatalogSalesInvoiceSupport
{
    /**
     * @param array<string, mixed> $filters
     * @return array{items: list<array<string, mixed>>, total_count: int}
     */
    public function listSalesInvoices(string $companyId, string $branchId, array $filters): array
    {
        $page = max(1, (int) ($filters['page'] ?? 1));
        $pageSize = min(max((int) ($filters['page_size'] ?? 50), 1), 200);
        $offset = ($page - 1) * $pageSize;

        $where = 'company_id = :company_id AND branch_id = :branch_id AND deleted_at IS NULL';
        $params = ['company_id' => $companyId, 'branch_id' => $branchId];

        if (isset($filters['customer_id']) && Uuid::isValid((string) $filters['customer_id'])) {
            $where .= ' AND customer_id = :customer_id';
            $params['customer_id'] = (string) $filters['customer_id'];
        }
        if (isset($filters['status']) && trim((string) $filters['status']) !== '') {
            $where .= ' AND invoice_status = :status';
            $params['status'] = (string) $filters['status'];
        } else {
            $where .= ' AND invoice_status = \'draft\'';
        }

        $countStmt = $this->db->pdo()->prepare("SELECT COUNT(*) FROM sales_invoices WHERE {$where}");
        $countStmt->execute($params);
        $total = (int) $countStmt->fetchColumn();

        $txnSelect = $this->catalogSalesInvoiceHasTransactionVersion()
            ? ', transaction_version'
            : '';

        $sql = "SELECT id, company_id, branch_id, customer_id, invoice_number, invoice_date,
                       invoice_status, payment_type, line_subtotal, discount_amount, tax_percent,
                       total, paid_amount, notes, row_version{$txnSelect}, created_at, updated_at
                FROM sales_invoices
                WHERE {$where}
                ORDER BY updated_at DESC
                LIMIT :limit OFFSET :offset";
        $stmt = $this->db->pdo()->prepare($sql);
        foreach ($params as $key => $value) {
            $stmt->bindValue(':' . $key, $value);
        }
        $stmt->bindValue(':limit', $pageSize, PDO::PARAM_INT);
        $stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
        $stmt->execute();
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $items = [];
        foreach (is_array($rows) ? $rows : [] as $row) {
            $items[] = $this->mapSalesInvoiceListRow(is_array($row) ? $row : []);
        }

        return ['items' => $items, 'total_count' => $total];
    }

    /** @return array<string, mixed>|null */
    public function getSalesInvoice(string $companyId, string $id, bool $includeDeleted = false): ?array
    {
        $sql = 'SELECT * FROM sales_invoices WHERE id = :id AND company_id = :company_id';
        if (!$includeDeleted) {
            $sql .= ' AND deleted_at IS NULL';
        }
        $sql .= ' LIMIT 1';

        $stmt = $this->db->pdo()->prepare($sql);
        $stmt->execute(['id' => $id, 'company_id' => $companyId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!is_array($row)) {
            return null;
        }

        return $this->mapSalesInvoiceDetailRow($row);
    }

    /**
     * @param array<string, mixed> $data
     * @return array<string, mixed>
     */
    public function createSalesInvoiceDraft(
        string $companyId,
        string $branchId,
        string $id,
        array $data,
        string $createdByUserId,
        ?string $originDeviceId = null,
    ): array {
        $existing = $this->getSalesInvoiceRow($companyId, $id, true);
        if ($existing !== null && ($existing['deleted_at'] ?? null) === null) {
            throw new HttpException('conflict', 'Invoice id already exists', 409);
        }

        $aggregate = $this->buildAggregateFromRestPayload($companyId, $branchId, $id, $data, $createdByUserId);
        $header = $aggregate['header'];
        $lines = $aggregate['lines'];

        $pdo = $this->db->pdo();
        $hasTxnVersion = $this->catalogSalesInvoiceHasTransactionVersion();

        if ($hasTxnVersion) {
            $stmt = $pdo->prepare(
                'INSERT INTO sales_invoices (
                    id, company_id, branch_id, customer_id, invoice_date, invoice_status,
                    payment_type, line_subtotal, discount_amount, tax_percent, total, paid_amount,
                    notes, created_by_user_id, origin_device_id, transaction_version, row_version
                 ) VALUES (
                    :id, :company_id, :branch_id, :customer_id, :invoice_date, \'draft\',
                    :payment_type, :line_subtotal, :discount_amount, :tax_percent, :total, :paid_amount,
                    :notes, :created_by_user_id, :origin_device_id, :transaction_version, 1
                 ) RETURNING row_version, transaction_version',
            );
        } else {
            $stmt = $pdo->prepare(
                'INSERT INTO sales_invoices (
                    id, company_id, branch_id, customer_id, invoice_date, invoice_status,
                    payment_type, line_subtotal, discount_amount, tax_percent, total, paid_amount,
                    notes, created_by_user_id, origin_device_id, row_version
                 ) VALUES (
                    :id, :company_id, :branch_id, :customer_id, :invoice_date, \'draft\',
                    :payment_type, :line_subtotal, :discount_amount, :tax_percent, :total, :paid_amount,
                    :notes, :created_by_user_id, :origin_device_id, 1
                 ) RETURNING row_version',
            );
        }
        $params = [
            'id' => $id,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'customer_id' => $header['customer_id'] ?? null,
            'invoice_date' => $header['invoice_date'],
            'payment_type' => $header['payment_type'],
            'line_subtotal' => $header['line_subtotal'],
            'discount_amount' => $header['discount_amount'],
            'tax_percent' => $header['tax_percent'],
            'total' => $header['total'],
            'paid_amount' => $header['paid_amount'],
            'notes' => $header['notes'],
            'created_by_user_id' => $createdByUserId,
            'origin_device_id' => $originDeviceId,
        ];
        if ($hasTxnVersion) {
            $params['transaction_version'] = 0;
        }
        $stmt->execute($params);
        $this->replaceSalesInvoiceLinesRest($pdo, $companyId, $branchId, $id, $lines);

        $detail = $this->getSalesInvoice($companyId, $id);
        if ($detail === null) {
            throw new RuntimeException('Sales invoice create failed');
        }

        return $detail;
    }

    /**
     * @param array<string, mixed> $data
     * @return array<string, mixed>
     */
    public function updateSalesInvoiceDraft(string $companyId, string $id, array $data): array
    {
        $existing = $this->requireDraftInvoice($companyId, $id);
        $this->assertRestRowVersion($existing, $data);

        $branchId = (string) $existing['branch_id'];
        $aggregate = $this->buildAggregateFromRestPayload(
            $companyId,
            $branchId,
            $id,
            $data,
            (string) $existing['created_by_user_id'],
            $existing,
        );
        $header = $aggregate['header'];
        $lines = $aggregate['lines'];

        $pdo = $this->db->pdo();
        $hasTxnVersion = $this->catalogSalesInvoiceHasTransactionVersion();
        $txnSet = $hasTxnVersion
            ? 'transaction_version = GREATEST(transaction_version, :transaction_version),'
            : '';
        $txnReturn = $hasTxnVersion ? ', transaction_version' : '';

        $stmt = $pdo->prepare(
            "UPDATE sales_invoices SET
                customer_id = :customer_id,
                invoice_date = :invoice_date,
                payment_type = :payment_type,
                line_subtotal = :line_subtotal,
                discount_amount = :discount_amount,
                tax_percent = :tax_percent,
                total = :total,
                paid_amount = :paid_amount,
                notes = :notes,
                {$txnSet}
                updated_at = now()
             WHERE id = :id AND company_id = :company_id AND invoice_status = 'draft' AND deleted_at IS NULL
             RETURNING row_version{$txnReturn}",
        );
        $updateParams = [
            'id' => $id,
            'company_id' => $companyId,
            'customer_id' => $header['customer_id'] ?? null,
            'invoice_date' => $header['invoice_date'],
            'payment_type' => $header['payment_type'],
            'line_subtotal' => $header['line_subtotal'],
            'discount_amount' => $header['discount_amount'],
            'tax_percent' => $header['tax_percent'],
            'total' => $header['total'],
            'paid_amount' => $header['paid_amount'],
            'notes' => $header['notes'],
        ];
        if ($hasTxnVersion) {
            $updateParams['transaction_version'] = (int) ($header['transaction_version']
                ?? ((int) ($existing['transaction_version'] ?? 0) + 1));
        }
        $stmt->execute($updateParams);
        $this->replaceSalesInvoiceLinesRest($pdo, $companyId, $branchId, $id, $lines);

        $detail = $this->getSalesInvoice($companyId, $id);
        if ($detail === null) {
            throw new RuntimeException('Sales invoice update failed');
        }

        return $detail;
    }

    /** @return array<string, mixed> */
    public function deleteSalesInvoiceDraft(string $companyId, string $id): array
    {
        $existing = $this->requireDraftInvoice($companyId, $id);
        $stmt = $this->db->pdo()->prepare(
            'UPDATE sales_invoices SET deleted_at = now(), updated_at = now()
             WHERE id = :id AND company_id = :company_id AND invoice_status = \'draft\'
             RETURNING row_version',
        );
        $stmt->execute(['id' => $id, 'company_id' => $companyId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return [
            'id' => $id,
            'status' => 'cancelled',
            'row_version' => is_array($row) ? (int) $row['row_version'] : (int) $existing['row_version'],
            'deleted' => true,
        ];
    }

    /** @return array<string, mixed> */
    private function requireDraftInvoice(string $companyId, string $id): array
    {
        $row = $this->getSalesInvoiceRow($companyId, $id);
        if ($row === null || ($row['deleted_at'] ?? null) !== null) {
            throw new HttpException('not_found', 'Draft invoice not found', 404);
        }
        if (($row['invoice_status'] ?? '') !== 'draft') {
            throw new HttpException('invoice_not_editable', 'Only draft invoices can be edited', 409);
        }

        return $row;
    }

    /** @return array<string, mixed>|null */
    private function getSalesInvoiceRow(string $companyId, string $id, bool $includeDeleted = false): ?array
    {
        $sql = 'SELECT * FROM sales_invoices WHERE id = :id AND company_id = :company_id';
        if (!$includeDeleted) {
            $sql .= ' AND deleted_at IS NULL';
        }
        $sql .= ' LIMIT 1';
        $stmt = $this->db->pdo()->prepare($sql);
        $stmt->execute(['id' => $id, 'company_id' => $companyId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
    }

    /** @param array<string, mixed> $row @return array<string, mixed> */
    private function mapSalesInvoiceListRow(array $row): array
    {
        return [
            'id' => (string) $row['id'],
            'company_id' => (string) $row['company_id'],
            'branch_id' => (string) $row['branch_id'],
            'customer_id' => $row['customer_id'],
            'invoice_number' => $row['invoice_number'],
            'invoice_date' => $row['invoice_date'],
            'status' => (string) $row['invoice_status'],
            'payment_type' => (string) $row['payment_type'],
            'line_subtotal' => (float) $row['line_subtotal'],
            'discount_amount' => (float) $row['discount_amount'],
            'tax_percent' => (float) $row['tax_percent'],
            'grand_total' => (float) $row['total'],
            'paid_amount' => (float) $row['paid_amount'],
            'row_version' => (int) $row['row_version'],
            'transaction_version' => (int) ($row['transaction_version'] ?? 0),
            'created_at' => $row['created_at'],
        ];
    }

    /** @param array<string, mixed> $row @return array<string, mixed> */
    private function mapSalesInvoiceDetailRow(array $row): array
    {
        $lines = $this->fetchSalesInvoiceLines((string) $row['id']);

        return [
            ...$this->mapSalesInvoiceListRow($row),
            'notes' => $row['notes'],
            'items' => $lines,
        ];
    }

    /** @return list<array<string, mixed>> */
    private function fetchSalesInvoiceLines(string $invoiceId): array
    {
        $stmt = $this->db->pdo()->prepare(
            'SELECT id, product_id, quantity, unit_price, line_total
             FROM sales_invoice_items WHERE invoice_id = :invoice_id ORDER BY id',
        );
        $stmt->execute(['invoice_id' => $invoiceId]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        $items = [];
        foreach (is_array($rows) ? $rows : [] as $row) {
            if (!is_array($row)) {
                continue;
            }
            $items[] = [
                'id' => (string) $row['id'],
                'line_id' => (string) $row['id'],
                'product_id' => (string) $row['product_id'],
                'quantity' => (float) $row['quantity'],
                'unit_price' => (float) $row['unit_price'],
                'line_total' => (float) $row['line_total'],
            ];
        }

        return $items;
    }

    /**
     * @param array<string, mixed> $data
     * @param array<string, mixed>|null $existing
     * @return array{header: array<string, mixed>, lines: list<array<string, mixed>>}
     */
    private function buildAggregateFromRestPayload(
        string $companyId,
        string $branchId,
        string $id,
        array $data,
        string $createdByUserId,
        ?array $existing = null,
    ): array {
        $items = is_array($data['items'] ?? null) ? $data['items'] : [];
        $lines = [];
        $lineSubtotal = 0.0;
        foreach ($items as $item) {
            if (!is_array($item)) {
                continue;
            }
            $lineId = (string) ($item['id'] ?? $item['line_id'] ?? Uuid::v4());
            $quantity = (float) ($item['quantity'] ?? 0);
            $unitPrice = (float) ($item['unit_price'] ?? 0);
            $lineTotal = (float) ($item['line_total'] ?? ($quantity * $unitPrice));
            $lineSubtotal += $lineTotal;
            $lines[] = [
                'line_id' => $lineId,
                'id' => $lineId,
                'product_id' => (string) ($item['product_id'] ?? ''),
                'quantity' => $quantity,
                'unit_price' => $unitPrice,
                'line_total' => $lineTotal,
            ];
        }

        $discount = (float) ($data['discount_amount'] ?? $existing['discount_amount'] ?? 0);
        $taxPercent = (float) ($data['tax_percent'] ?? $existing['tax_percent'] ?? 0);
        $total = (float) ($data['grand_total'] ?? $data['total'] ?? max(0, $lineSubtotal - $discount));
        $paidAmount = (float) ($data['paid_amount'] ?? $existing['paid_amount'] ?? 0);

        return [
            'header' => [
                'id' => $id,
                'company_id' => $companyId,
                'branch_id' => $branchId,
                'document_type' => 'sales_invoice',
                'status' => 'draft',
                'customer_id' => $data['customer_id'] ?? $existing['customer_id'] ?? null,
                'invoice_date' => $this->parseRestDate($data['invoice_date'] ?? $existing['invoice_date'] ?? null),
                'payment_type' => (string) ($data['payment_type'] ?? $existing['payment_type'] ?? 'cash'),
                'line_subtotal' => $lineSubtotal,
                'discount_amount' => $discount,
                'tax_percent' => $taxPercent,
                'total' => $total,
                'paid_amount' => $paidAmount,
                'notes' => $data['notes'] ?? $existing['notes'] ?? null,
                'created_by_user_id' => $createdByUserId,
                'transaction_version' => (int) ($data['transaction_version'] ?? ((int) ($existing['transaction_version'] ?? 0) + 1)),
            ],
            'lines' => $lines,
        ];
    }

    /**
     * @param list<array<string, mixed>> $lines
     */
    private function replaceSalesInvoiceLinesRest(
        PDO $pdo,
        string $companyId,
        string $branchId,
        string $invoiceId,
        array $lines,
    ): void {
        $delete = $pdo->prepare('DELETE FROM sales_invoice_items WHERE invoice_id = :invoice_id');
        $delete->execute(['invoice_id' => $invoiceId]);

        $insert = $pdo->prepare(
            'INSERT INTO sales_invoice_items (
                id, invoice_id, company_id, branch_id, product_id, quantity, unit_price, line_total
             ) VALUES (
                :id, :invoice_id, :company_id, :branch_id, :product_id, :quantity, :unit_price, :line_total
             )',
        );

        foreach ($lines as $line) {
            $insert->execute([
                'id' => (string) ($line['line_id'] ?? $line['id']),
                'invoice_id' => $invoiceId,
                'company_id' => $companyId,
                'branch_id' => $branchId,
                'product_id' => (string) ($line['product_id'] ?? ''),
                'quantity' => (float) ($line['quantity'] ?? 0),
                'unit_price' => (float) ($line['unit_price'] ?? 0),
                'line_total' => (float) ($line['line_total'] ?? 0),
            ]);
        }
    }

    /** @param array<string, mixed> $existing @param array<string, mixed> $data */
    private function assertRestRowVersion(array $existing, array $data): void
    {
        if (!array_key_exists('row_version', $data)) {
            return;
        }
        $incoming = (int) $data['row_version'];
        $local = (int) ($existing['row_version'] ?? 0);
        if ($incoming < $local) {
            throw new HttpException('conflict', 'Stale row_version', 409);
        }
    }

    private function parseRestDate(mixed $value): string
    {
        if ($value === null || trim((string) $value) === '') {
            return gmdate('Y-m-d H:i:s');
        }
        $time = strtotime((string) $value);

        return $time === false ? gmdate('Y-m-d H:i:s') : gmdate('Y-m-d H:i:s', $time);
    }

    private function catalogSalesInvoiceHasTransactionVersion(): bool
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
