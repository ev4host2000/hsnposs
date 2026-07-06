<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Support;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Modules\Sync\Repositories\SyncRepositorySupport;
use RuntimeException;

/**
 * Draft-only LWW for inventory adjustments — header + metadata, no lines/accounting/cash.
 */
trait InventoryAdjustmentDraftLww
{
    use InventoryAdjustmentPostLww;

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
            return $this->applyInventoryAdjustmentPost(
                $companyId,
                $branchId,
                $entityId,
                $payloadJson,
                $clientRowVersion,
                $originDeviceId,
            );
        }

        if (in_array($operation, ['cancel', 'delete'], true)) {
            return $this->cancelInventoryAdjustmentDraft(
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

        $existing = $this->fetchInventoryAdjustmentRow($companyId, $entityId);
        if ($operation === 'create' && $existing !== null && ($existing['deleted_at'] ?? null) === null) {
            throw new HttpException('conflict', 'Adjustment already exists', 409);
        }
        if ($operation === 'update') {
            if ($existing === null || ($existing['deleted_at'] ?? null) !== null) {
                throw new HttpException('not_found', 'Draft adjustment not found', 404);
            }
            if (($existing['adjustment_status'] ?? '') !== 'draft') {
                throw new HttpException('adjustment_not_editable', 'Only draft adjustments can be updated', 409);
            }
        }

        $productId = $this->optionalString($header['product_id'] ?? null);
        if ($productId === null) {
            throw new HttpException('validation_error', 'product_id is required', 400);
        }

        $createdBy = $this->optionalString($header['created_by_user_id'] ?? null)
            ?? $this->resolveDefaultUserId($companyId);
        if ($createdBy === null) {
            throw new HttpException('validation_error', 'created_by_user_id is required', 400);
        }

        $adjustmentDate = $this->parseAdjustmentDate($header['adjustment_date'] ?? null);
        $quantityDelta = (float) ($header['quantity_delta'] ?? 0);
        $notes = $this->optionalString($header['notes'] ?? null);
        $reason = $this->normalizeAdjustmentReason($header);
        $transactionVersion = max(0, (int) ($header['transaction_version'] ?? 0));
        $rowVersion = max(1, (int) ($header['row_version'] ?? $clientRowVersion));

        $pdo = $this->db->pdo();
        $hasTxnVersion = $this->inventoryAdjustmentHasTransactionVersion();

        if ($hasTxnVersion) {
            $sql = 'INSERT INTO inventory_adjustments (
                        id, company_id, branch_id, product_id, quantity_delta, adjustment_date,
                        adjustment_status, notes, reason, created_by_user_id, origin_device_id,
                        transaction_version, row_version, created_at, updated_at, deleted_at
                    ) VALUES (
                        :id, :company_id, :branch_id, :product_id, :quantity_delta, :adjustment_date,
                        \'draft\', :notes, :reason, :created_by_user_id, :origin_device_id,
                        :transaction_version, :row_version, now(), now(), NULL
                    )
                    ON CONFLICT (id) DO UPDATE SET
                        product_id = EXCLUDED.product_id,
                        quantity_delta = EXCLUDED.quantity_delta,
                        adjustment_date = EXCLUDED.adjustment_date,
                        adjustment_status = \'draft\',
                        notes = EXCLUDED.notes,
                        reason = EXCLUDED.reason,
                        origin_device_id = COALESCE(EXCLUDED.origin_device_id, inventory_adjustments.origin_device_id),
                        transaction_version = GREATEST(inventory_adjustments.transaction_version, EXCLUDED.transaction_version),
                        row_version = GREATEST(inventory_adjustments.row_version, EXCLUDED.row_version),
                        updated_at = now(),
                        deleted_at = NULL
                    RETURNING row_version, transaction_version, adjustment_status';
        } else {
            $sql = 'INSERT INTO inventory_adjustments (
                        id, company_id, branch_id, product_id, quantity_delta, adjustment_date,
                        adjustment_status, notes, reason, created_by_user_id, origin_device_id,
                        row_version, created_at, updated_at, deleted_at
                    ) VALUES (
                        :id, :company_id, :branch_id, :product_id, :quantity_delta, :adjustment_date,
                        \'draft\', :notes, :reason, :created_by_user_id, :origin_device_id,
                        :row_version, now(), now(), NULL
                    )
                    ON CONFLICT (id) DO UPDATE SET
                        product_id = EXCLUDED.product_id,
                        quantity_delta = EXCLUDED.quantity_delta,
                        adjustment_date = EXCLUDED.adjustment_date,
                        adjustment_status = \'draft\',
                        notes = EXCLUDED.notes,
                        reason = EXCLUDED.reason,
                        origin_device_id = COALESCE(EXCLUDED.origin_device_id, inventory_adjustments.origin_device_id),
                        row_version = GREATEST(inventory_adjustments.row_version, EXCLUDED.row_version),
                        updated_at = now(),
                        deleted_at = NULL
                    RETURNING row_version, adjustment_status';
        }

        $stmt = $pdo->prepare($sql);
        $params = [
            'id' => $entityId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'product_id' => $productId,
            'quantity_delta' => $quantityDelta,
            'adjustment_date' => $adjustmentDate,
            'notes' => $notes,
            'reason' => $reason,
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
            throw new RuntimeException('Inventory adjustment upsert failed');
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
    protected function cancelInventoryAdjustmentDraft(
        string $companyId,
        string $branchId,
        string $entityId,
        int $clientRowVersion,
        ?string $originDeviceId,
    ): array {
        $existing = $this->fetchInventoryAdjustmentRow($companyId, $entityId);
        if ($existing !== null && ($existing['adjustment_status'] ?? '') !== 'draft') {
            throw new HttpException('adjustment_not_editable', 'Only draft adjustments can be deleted', 409);
        }

        $deleted = $this->softDeleteRow('inventory_adjustments', $companyId, $entityId, $clientRowVersion);

        return $this->buildAggregateEnvelope(
            $companyId,
            $branchId,
            $entityId,
            [
                'id' => $entityId,
                'company_id' => $companyId,
                'branch_id' => $branchId,
                'document_type' => 'inventory_adjustment',
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
    protected function fetchInventoryAdjustmentRow(string $companyId, string $entityId): ?array
    {
        $txnCol = $this->inventoryAdjustmentHasTransactionVersion() ? ', transaction_version' : '';
        $postedCol = $this->inventoryAdjustmentHasPostedAt() ? ', posted_at' : '';
        $stmt = $this->db->pdo()->prepare(
            'SELECT id, adjustment_status, row_version, deleted_at' . $txnCol . $postedCol . '
             FROM inventory_adjustments
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
            'document_type' => 'inventory_adjustment',
            'status' => $status,
            'row_version' => $rowVersion,
            'transaction_version' => $transactionVersion,
        ]);
        if ($deleted) {
            $normalizedHeader['deleted'] = true;
        }
        if (isset($header['product_id'])) {
            $normalizedHeader['product_id'] = $header['product_id'];
        }
        if (isset($header['quantity_delta'])) {
            $normalizedHeader['quantity_delta'] = $header['quantity_delta'];
        }
        if (isset($header['adjustment_date'])) {
            $normalizedHeader['adjustment_date'] = $header['adjustment_date'];
        }
        $reason = $this->normalizeAdjustmentReason($header);
        if ($reason !== null && $reason !== '') {
            $normalizedHeader['adjustment_reason'] = $reason;
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

    protected function parseAdjustmentDate(mixed $value): string
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
