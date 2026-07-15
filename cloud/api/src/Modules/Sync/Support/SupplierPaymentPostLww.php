<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Support;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Modules\Auth\Support\Uuid;

/**
 * Post handler for supplier payments — partner ledger + cash + finalize.
 */
trait SupplierPaymentPostLww
{
    /**
     * @param array<string, mixed> $payloadJson
     * @return array<string, mixed>
     */
    protected function applySupplierPaymentPost(
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

        $existing = $this->fetchSupplierPaymentRow($companyId, $entityId);
        if ($existing === null || ($existing['deleted_at'] ?? null) !== null) {
            // الترحيل وصل قبل create — أنشئ المسودة من حمولة post ثم أكمل.
            $headerTxnForDraft = max(0, (int) ($header['transaction_version'] ?? 0));
            $draftHeader = $header;
            $draftHeader['status'] = 'draft';
            $draftHeader['transaction_version'] = max(0, $headerTxnForDraft - 1);
            $draftHeader['row_version'] = max(
                1,
                (int) ($header['row_version'] ?? $clientRowVersion) - 1,
            );
            try {
                $this->applyDraftLww(
                    $companyId,
                    $branchId,
                    $entityId,
                    'create',
                    [
                        'aggregate' => [
                            'header' => $draftHeader,
                            'lines' => $lines,
                            'metadata' => [],
                        ],
                    ],
                    max(1, $clientRowVersion - 1),
                    $originDeviceId,
                );
            } catch (HttpException $e) {
                throw $e;
            }
            $existing = $this->fetchSupplierPaymentRow($companyId, $entityId);
            if ($existing === null || ($existing['deleted_at'] ?? null) !== null) {
                throw new HttpException('not_found', 'Draft payment not found', 404);
            }
        }

        $dbStatus = (string) ($existing['payment_status'] ?? '');
        $dbTxnVersion = (int) ($existing['transaction_version'] ?? 0);
        $headerTxnVersion = max(0, (int) ($header['transaction_version'] ?? 0));

        if ($dbStatus === 'posted') {
            if ($headerTxnVersion <= $dbTxnVersion) {
                return $this->buildSupplierPaymentPostAggregateEnvelope(
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
            throw new HttpException('already_posted', 'Payment already posted', 409);
        }

        if ($dbStatus !== 'draft') {
            throw new HttpException('payment_not_editable', 'Only draft payments can be posted', 409);
        }

        if ($headerTxnVersion !== $dbTxnVersion + 1 && $headerTxnVersion !== $dbTxnVersion) {
            throw new HttpException(
                'transaction_version_mismatch',
                'Invalid transaction_version for post',
                409,
            );
        }

        $supplierId = $this->optionalString($header['supplier_id'] ?? null);
        if ($supplierId === null || !Uuid::isValid($supplierId)) {
            throw new HttpException('validation_error', 'supplier_id is required for post', 400);
        }

        $amount = (float) ($header['amount'] ?? 0);
        if ($amount <= 0) {
            throw new HttpException('validation_error', 'amount must be > 0 for post', 400);
        }

        $createdBy = $this->optionalString($header['created_by_user_id'] ?? null)
            ?? $this->resolveDefaultUserId($companyId);
        if ($createdBy === null) {
            throw new HttpException('validation_error', 'created_by_user_id is required', 400);
        }

        $accounting = $this->extractPostSection($aggregate, $metadata, 'accounting');
        $cash = $this->extractPostSection($aggregate, $metadata, 'cash');

        if ($accounting === [] || $cash === []) {
            throw new HttpException('validation_error', 'Post aggregate requires accounting and cash', 400);
        }

        $pdo = $this->db->pdo();
        $postedAt = gmdate('Y-m-d H:i:s');

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
                (string) ($entry['entry_type'] ?? 'supplier_payment'),
                (string) ($entry['reference_type'] ?? 'supplier_payment'),
                (string) ($entry['reference_id'] ?? $entityId),
                (float) ($entry['amount_signed'] ?? 0),
                $this->parsePaymentDate($entry['entry_date'] ?? null),
                $createdBy,
                $this->optionalString($entry['notes'] ?? null),
                $this->optionalString($entry['voucher_number'] ?? null),
            );
        }

        foreach ($cash as $txn) {
            if (!is_array($txn)) {
                continue;
            }
            $txnId = (string) ($txn['transaction_id'] ?? $txn['id'] ?? '');
            if ($txnId === '' || !Uuid::isValid($txnId)) {
                throw new HttpException('validation_error', 'Invalid cash transaction id', 400);
            }
            $this->applyCashTransactionIdempotent(
                $pdo,
                $companyId,
                $branchId,
                $txnId,
                (string) ($txn['transaction_type'] ?? 'out'),
                (float) ($txn['amount'] ?? 0),
                (string) ($txn['description'] ?? ''),
                (string) ($txn['reference_type'] ?? 'supplier_payment'),
                (string) ($txn['reference_id'] ?? $entityId),
                $this->parsePaymentDate($txn['transaction_date'] ?? null),
                $createdBy,
            );
        }

        $nextTxnVersion = $dbTxnVersion + 1;
        $nextRowVersion = max(
            (int) ($existing['row_version'] ?? 1),
            (int) ($header['row_version'] ?? $clientRowVersion),
            $clientRowVersion,
        ) + 1;

        $hasPostedAt = $this->supplierPaymentHasPostedAt();
        $hasTxnVersion = $this->supplierPaymentHasTransactionVersion();

        $setParts = [
            'payment_status = \'posted\'',
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

        $returnCols = 'row_version, payment_status';
        if ($hasTxnVersion) {
            $returnCols = 'row_version, transaction_version, payment_status';
        }

        $stmt = $pdo->prepare(
            'UPDATE supplier_payments SET ' . implode(', ', $setParts) . '
             WHERE id = :id AND company_id = :company_id AND payment_status = \'draft\'
             RETURNING ' . $returnCols,
        );
        $stmt->execute($params);
        $saved = $stmt->fetch(\PDO::FETCH_ASSOC);
        if (!is_array($saved)) {
            $refetched = $this->fetchSupplierPaymentRow($companyId, $entityId);
            if ($refetched !== null && (string) ($refetched['payment_status'] ?? '') === 'posted') {
                return $this->buildSupplierPaymentPostAggregateEnvelope(
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
            throw new HttpException('posting_conflict', 'Payment post conflict — draft lock failed', 409);
        }

        $normalizedHeader = array_merge($header, [
            'status' => 'posted',
            'transaction_version' => (int) ($saved['transaction_version'] ?? $nextTxnVersion),
            'row_version' => (int) $saved['row_version'],
            'posted_at' => $postedAt,
        ]);

        return $this->buildSupplierPaymentPostAggregateEnvelope(
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

    protected function applyPartnerLedgerIdempotent(
        \PDO $pdo,
        string $companyId,
        string $branchId,
        string $entryId,
        string $partnerKind,
        string $partnerId,
        string $entryType,
        string $referenceType,
        string $referenceId,
        float $amountSigned,
        string $entryDate,
        string $createdBy,
        ?string $notes,
        ?string $voucherNumber = null,
    ): void {
        $exists = $pdo->prepare('SELECT 1 FROM partner_ledger WHERE id = :id LIMIT 1');
        $exists->execute(['id' => $entryId]);
        if ($exists->fetchColumn()) {
            return;
        }

        $insert = $pdo->prepare(
            'INSERT INTO partner_ledger (
                id, company_id, branch_id, partner_kind, partner_id, entry_type,
                reference_type, reference_id, amount_signed, entry_date,
                created_by_user_id, notes, voucher_number
             ) VALUES (
                :id, :company_id, :branch_id, :partner_kind, :partner_id, :entry_type,
                :reference_type, :reference_id, :amount_signed, :entry_date,
                :created_by_user_id, :notes, :voucher_number
             )',
        );
        $insert->execute([
            'id' => $entryId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'partner_kind' => $partnerKind,
            'partner_id' => $partnerId,
            'entry_type' => $entryType,
            'reference_type' => $referenceType,
            'reference_id' => $referenceId,
            'amount_signed' => $amountSigned,
            'entry_date' => $entryDate,
            'created_by_user_id' => $createdBy,
            'notes' => $notes,
            'voucher_number' => $voucherNumber,
        ]);
    }

    protected function applyCashTransactionIdempotent(
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

    /**
     * @param array<string, mixed> $header
     * @param list<array<string, mixed>> $lines
     * @param array<string, mixed> $metadata
     * @param array<string, mixed> $sourceAggregate
     * @return array<string, mixed>
     */
    protected function buildSupplierPaymentPostAggregateEnvelope(
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
        $accounting = $this->extractPostSection($sourceAggregate, $metadata, 'accounting');
        $cash = $this->extractPostSection($sourceAggregate, $metadata, 'cash');

        $normalizedHeader = array_merge($header, [
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'document_type' => 'supplier_payment',
            'status' => 'posted',
            'row_version' => $rowVersion,
            'transaction_version' => $transactionVersion,
        ]);

        $normalizedMetadata = array_merge(
            ['payload_schema_version' => 1],
            $metadata,
            [
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
                'accounting' => $accounting,
                'cash' => $cash,
                'metadata' => $normalizedMetadata,
            ],
            'row_version' => $rowVersion,
            'deleted' => false,
        ];
    }

    protected function supplierPaymentHasPostedAt(): bool
    {
        static $cached = null;
        if ($cached !== null) {
            return $cached;
        }

        $stmt = $this->db->pdo()->prepare(
            'SELECT 1 FROM information_schema.columns
             WHERE table_schema = current_schema()
               AND table_name = \'supplier_payments\'
               AND column_name = \'posted_at\'
             LIMIT 1',
        );
        $stmt->execute();
        $cached = (bool) $stmt->fetchColumn();

        return $cached;
    }

    protected function supplierPaymentHasTransactionVersion(): bool
    {
        static $cached = null;
        if ($cached !== null) {
            return $cached;
        }

        $stmt = $this->db->pdo()->prepare(
            'SELECT 1 FROM information_schema.columns
             WHERE table_schema = current_schema()
               AND table_name = \'supplier_payments\'
               AND column_name = \'transaction_version\'
             LIMIT 1',
        );
        $stmt->execute();
        $cached = (bool) $stmt->fetchColumn();

        return $cached;
    }
}
