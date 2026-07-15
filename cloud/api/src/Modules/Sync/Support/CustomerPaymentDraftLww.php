<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Support;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Modules\Sync\Repositories\SyncRepositorySupport;
use RuntimeException;

/**
 * Draft-only LWW for customer payments — header + metadata, no lines/accounting/cash.
 */
trait CustomerPaymentDraftLww
{
    use CustomerPaymentPostLww;

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
            return $this->applyCustomerPaymentPost(
                $companyId,
                $branchId,
                $entityId,
                $payloadJson,
                $clientRowVersion,
                $originDeviceId,
            );
        }

        if (in_array($operation, ['cancel', 'delete'], true)) {
            return $this->cancelCustomerPaymentDraft(
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

        $existing = $this->fetchCustomerPaymentRow($companyId, $entityId);
        // Idempotent create: already on server → success (do not rewrite posted rows).
        if ($operation === 'create' && $existing !== null && ($existing['deleted_at'] ?? null) === null) {
            $status = (string) ($existing['payment_status'] ?? 'draft');
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
            } elseif (($existing['payment_status'] ?? '') !== 'draft') {
                throw new HttpException('payment_not_editable', 'Only draft payments can be updated', 409);
            }
        }

        $createdBy = $this->optionalString($header['created_by_user_id'] ?? null)
            ?? $this->resolveDefaultUserId($companyId);
        if ($createdBy === null) {
            throw new HttpException('validation_error', 'created_by_user_id is required', 400);
        }

        $customerId = $this->optionalString($header['customer_id'] ?? null);
        $paymentDate = $this->parsePaymentDate($header['payment_date'] ?? null);
        $paymentMethod = trim((string) ($header['payment_method'] ?? 'cash'));
        if ($paymentMethod === '') {
            $paymentMethod = 'cash';
        }

        $amount = (float) ($header['amount'] ?? 0);
        $voucherNumber = $this->optionalString($header['voucher_number'] ?? null);
        $notes = $this->optionalString($header['notes'] ?? null);
        $transactionVersion = max(0, (int) ($header['transaction_version'] ?? 0));
        $rowVersion = max(1, (int) ($header['row_version'] ?? $clientRowVersion));

        $pdo = $this->db->pdo();
        $hasTxnVersion = $this->customerPaymentHasTransactionVersion();

        if ($hasTxnVersion) {
            $sql = 'INSERT INTO customer_payments (
                        id, company_id, branch_id, customer_id, amount, payment_date,
                        payment_method, voucher_number, notes, payment_status,
                        created_by_user_id, origin_device_id,
                        transaction_version, row_version, created_at, updated_at, deleted_at
                    ) VALUES (
                        :id, :company_id, :branch_id, :customer_id, :amount, :payment_date,
                        :payment_method, :voucher_number, :notes, \'draft\',
                        :created_by_user_id, :origin_device_id,
                        :transaction_version, :row_version, now(), now(), NULL
                    )
                    ON CONFLICT (id) DO UPDATE SET
                        customer_id = EXCLUDED.customer_id,
                        amount = EXCLUDED.amount,
                        payment_date = EXCLUDED.payment_date,
                        payment_method = EXCLUDED.payment_method,
                        voucher_number = EXCLUDED.voucher_number,
                        notes = EXCLUDED.notes,
                        payment_status = \'draft\',
                        origin_device_id = COALESCE(EXCLUDED.origin_device_id, customer_payments.origin_device_id),
                        transaction_version = GREATEST(customer_payments.transaction_version, EXCLUDED.transaction_version),
                        row_version = GREATEST(customer_payments.row_version, EXCLUDED.row_version),
                        updated_at = now(),
                        deleted_at = NULL
                    RETURNING row_version, transaction_version, payment_status';
        } else {
            $sql = 'INSERT INTO customer_payments (
                        id, company_id, branch_id, customer_id, amount, payment_date,
                        payment_method, voucher_number, notes, payment_status,
                        created_by_user_id, origin_device_id,
                        row_version, created_at, updated_at, deleted_at
                    ) VALUES (
                        :id, :company_id, :branch_id, :customer_id, :amount, :payment_date,
                        :payment_method, :voucher_number, :notes, \'draft\',
                        :created_by_user_id, :origin_device_id,
                        :row_version, now(), now(), NULL
                    )
                    ON CONFLICT (id) DO UPDATE SET
                        customer_id = EXCLUDED.customer_id,
                        amount = EXCLUDED.amount,
                        payment_date = EXCLUDED.payment_date,
                        payment_method = EXCLUDED.payment_method,
                        voucher_number = EXCLUDED.voucher_number,
                        notes = EXCLUDED.notes,
                        payment_status = \'draft\',
                        origin_device_id = COALESCE(EXCLUDED.origin_device_id, customer_payments.origin_device_id),
                        row_version = GREATEST(customer_payments.row_version, EXCLUDED.row_version),
                        updated_at = now(),
                        deleted_at = NULL
                    RETURNING row_version, payment_status';
        }

        $stmt = $pdo->prepare($sql);
        $params = [
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'customer_id' => $customerId,
            'amount' => $amount,
            'payment_date' => $paymentDate,
            'payment_method' => $paymentMethod,
            'voucher_number' => $voucherNumber,
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
            throw new RuntimeException('Customer payment upsert failed');
        }

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
    protected function cancelCustomerPaymentDraft(
        string $companyId,
        string $branchId,
        string $entityId,
        int $clientRowVersion,
        ?string $originDeviceId,
    ): array {
        $existing = $this->fetchCustomerPaymentRow($companyId, $entityId);
        if ($existing !== null && ($existing['payment_status'] ?? '') !== 'draft') {
            throw new HttpException('payment_not_editable', 'Only draft payments can be deleted', 409);
        }

        $deleted = $this->softDeleteRow('customer_payments', $companyId, $entityId, $clientRowVersion);

        return $this->buildAggregateEnvelope(
            $companyId,
            $branchId,
            $entityId,
            [
                'id' => $entityId,
                'company_id' => $companyId,
                'branch_id' => $branchId,
                'document_type' => 'customer_payment',
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
    protected function fetchCustomerPaymentRow(string $companyId, string $entityId): ?array
    {
        $txnCol = $this->customerPaymentHasTransactionVersion() ? ', transaction_version' : '';
        $postedCol = $this->customerPaymentHasPostedAt() ? ', posted_at' : '';
        $stmt = $this->db->pdo()->prepare(
            'SELECT id, payment_status, row_version, deleted_at' . $txnCol . $postedCol . '
             FROM customer_payments
             WHERE id = :id AND company_id = :company_id
             LIMIT 1',
        );
        $stmt->execute(['id' => $entityId, 'company_id' => $companyId]);
        $row = $stmt->fetch(\PDO::FETCH_ASSOC);

        return is_array($row) ? $row : null;
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
            'document_type' => 'customer_payment',
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

    protected function parsePaymentDate(mixed $value): string
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
}
