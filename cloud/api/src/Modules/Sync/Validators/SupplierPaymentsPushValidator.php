<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Validators;

use MizaCloud\Modules\Auth\Support\Uuid;

final class SupplierPaymentsPushValidator extends TransactionPushValidator
{
    protected function entityType(): string
    {
        return 'supplier_payment';
    }

    protected function entityLabel(): string
    {
        return 'Supplier payment';
    }

    /** @return list<string> */
    protected function supportedPushOperations(): array
    {
        return ['create', 'update', 'cancel', 'post'];
    }

    /** @param array<string, mixed> $payload @return list<string> */
    protected function validateTransactionPayload(array $payload, string $prefix): array
    {
        $operation = (string) ($payload['operation'] ?? '');
        if ($operation === 'post') {
            return $this->validatePostPayload($payload, $prefix);
        }

        $errors = [];
        $aggregate = $payload['aggregate'] ?? null;
        if (!is_array($aggregate)) {
            $errors[] = "{$prefix}.payload_json.aggregate:aggregate envelope is required";

            return $errors;
        }

        $header = $aggregate['header'] ?? null;
        if (!is_array($header)) {
            $errors[] = "{$prefix}.payload_json.aggregate.header:header is required";

            return $errors;
        }

        if (($header['document_type'] ?? '') !== $this->entityType()) {
            $errors[] = "{$prefix}.payload_json.aggregate.header.document_type:document_type mismatch";
        }

        if (($header['status'] ?? '') !== 'draft') {
            $errors[] = "{$prefix}.payload_json.aggregate.header.status:Only draft status is supported";
        }

        if (!is_string($header['id'] ?? null) || !Uuid::isValid((string) $header['id'])) {
            $errors[] = "{$prefix}.payload_json.aggregate.header.id:Valid header id is required";
        }

        $lines = $aggregate['lines'] ?? null;
        if (!is_array($lines)) {
            $errors[] = "{$prefix}.payload_json.aggregate.lines:lines array is required";
        }

        return array_merge($errors, $this->validateAggregateExtras($aggregate, $prefix));
    }

    /** @param array<string, mixed> $payload @return list<string> */
    private function validatePostPayload(array $payload, string $prefix): array
    {
        $errors = [];
        $aggregate = $payload['aggregate'] ?? null;
        if (!is_array($aggregate)) {
            $errors[] = "{$prefix}.payload_json.aggregate:aggregate envelope is required";

            return $errors;
        }

        $header = $aggregate['header'] ?? null;
        if (!is_array($header)) {
            $errors[] = "{$prefix}.payload_json.aggregate.header:header is required";

            return $errors;
        }

        if (($header['document_type'] ?? '') !== $this->entityType()) {
            $errors[] = "{$prefix}.payload_json.aggregate.header.document_type:document_type mismatch";
        }

        if (($header['status'] ?? '') !== 'posted') {
            $errors[] = "{$prefix}.payload_json.aggregate.header.status:Post requires posted status";
        }

        if (!is_string($header['id'] ?? null) || !Uuid::isValid((string) $header['id'])) {
            $errors[] = "{$prefix}.payload_json.aggregate.header.id:Valid header id is required";
        }

        $supplierId = (string) ($header['supplier_id'] ?? '');
        if ($supplierId === '' || !Uuid::isValid($supplierId)) {
            $errors[] = "{$prefix}.payload_json.aggregate.header.supplier_id:Valid supplier_id is required for post";
        }

        $amount = (float) ($header['amount'] ?? 0);
        if ($amount <= 0) {
            $errors[] = "{$prefix}.payload_json.aggregate.header.amount:amount must be > 0 for post";
        }

        $metadata = is_array($aggregate['metadata'] ?? null) ? $aggregate['metadata'] : [];
        $accounting = is_array($aggregate['accounting'] ?? null)
            ? $aggregate['accounting']
            : ($metadata['accounting'] ?? []);
        $cash = is_array($aggregate['cash'] ?? null)
            ? $aggregate['cash']
            : ($metadata['cash'] ?? []);

        if (!is_array($accounting) || $accounting === []) {
            $errors[] = "{$prefix}.payload_json.aggregate.accounting:accounting section is required for post";
        }
        if (!is_array($cash) || $cash === []) {
            $errors[] = "{$prefix}.payload_json.aggregate.cash:cash section is required for post";
        }

        return array_merge($errors, $this->validateAggregateExtras($aggregate, $prefix));
    }

    /** @param array<string, mixed> $aggregate @return list<string> */
    protected function validateAggregateExtras(array $aggregate, string $prefix): array
    {
        $errors = [];
        $header = is_array($aggregate['header'] ?? null) ? $aggregate['header'] : [];

        if (array_key_exists('created_by_user_id', $header)
            && !Uuid::isValid((string) $header['created_by_user_id'])) {
            $errors[] = "{$prefix}.payload_json.aggregate.header.created_by_user_id:Invalid UUID";
        }

        if (array_key_exists('supplier_id', $header)
            && $header['supplier_id'] !== null
            && (string) $header['supplier_id'] !== ''
            && !Uuid::isValid((string) $header['supplier_id'])) {
            $errors[] = "{$prefix}.payload_json.aggregate.header.supplier_id:Invalid UUID";
        }

        if (array_key_exists('amount', $header) && (float) ($header['amount'] ?? 0) < 0) {
            $errors[] = "{$prefix}.payload_json.aggregate.header.amount:amount must be >= 0";
        }

        return $errors;
    }
}
