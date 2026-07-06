<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Validators;

use MizaCloud\Modules\Auth\Support\Uuid;

final class InventoryAdjustmentsPushValidator extends TransactionPushValidator
{
    protected function entityType(): string
    {
        return 'inventory_adjustment';
    }

    protected function entityLabel(): string
    {
        return 'Inventory adjustment';
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

        $productId = (string) ($header['product_id'] ?? '');
        if ($productId === '' || !Uuid::isValid($productId)) {
            $errors[] = "{$prefix}.payload_json.aggregate.header.product_id:Valid product_id is required for post";
        }

        $quantityDelta = (float) ($header['quantity_delta'] ?? 0);
        if (abs($quantityDelta) < 1e-9) {
            $errors[] = "{$prefix}.payload_json.aggregate.header.quantity_delta:quantity_delta must be non-zero for post";
        }

        $metadata = is_array($aggregate['metadata'] ?? null) ? $aggregate['metadata'] : [];
        $inventory = is_array($aggregate['inventory'] ?? null)
            ? $aggregate['inventory']
            : ($metadata['inventory'] ?? []);

        if (!is_array($inventory) || $inventory === []) {
            $errors[] = "{$prefix}.payload_json.aggregate.inventory:inventory section is required for post";
        }

        return array_merge($errors, $this->validateAggregateExtras($aggregate, $prefix));
    }

    /** @param array<string, mixed> $aggregate @return list<string> */
    protected function validateAggregateExtras(array $aggregate, string $prefix): array
    {
        $errors = [];
        $header = is_array($aggregate['header'] ?? null) ? $aggregate['header'] : [];

        $productId = (string) ($header['product_id'] ?? '');
        if ($productId === '' || !Uuid::isValid($productId)) {
            $errors[] = "{$prefix}.payload_json.aggregate.header.product_id:Valid product_id required";
        }

        if (array_key_exists('created_by_user_id', $header)
            && !Uuid::isValid((string) $header['created_by_user_id'])) {
            $errors[] = "{$prefix}.payload_json.aggregate.header.created_by_user_id:Invalid UUID";
        }

        return $errors;
    }
}
