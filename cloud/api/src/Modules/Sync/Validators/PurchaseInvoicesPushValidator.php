<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Validators;

use MizaCloud\Modules\Auth\Support\Uuid;

final class PurchaseInvoicesPushValidator extends TransactionPushValidator
{
    protected function entityType(): string
    {
        return 'purchase_invoice';
    }

    protected function entityLabel(): string
    {
        return 'Purchase invoice';
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

        return parent::validateTransactionPayload($payload, $prefix);
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

        $SupplierId = (string) ($header['supplier_id'] ?? '');
        if ($SupplierId === '' || !Uuid::isValid($SupplierId)) {
            $errors[] = "{$prefix}.payload_json.aggregate.header.supplier_id:Valid supplier_id is required for post";
        }

        $lines = $aggregate['lines'] ?? null;
        if (!is_array($lines) || $lines === []) {
            $errors[] = "{$prefix}.payload_json.aggregate.lines:At least one line is required for post";
        }

        $metadata = is_array($aggregate['metadata'] ?? null) ? $aggregate['metadata'] : [];
        $inventory = is_array($aggregate['inventory'] ?? null)
            ? $aggregate['inventory']
            : ($metadata['inventory'] ?? []);
        $accounting = is_array($aggregate['accounting'] ?? null)
            ? $aggregate['accounting']
            : ($metadata['accounting'] ?? []);

        if (!is_array($inventory) || $inventory === []) {
            $errors[] = "{$prefix}.payload_json.aggregate.inventory:inventory section is required for post";
        }
        if (!is_array($accounting) || $accounting === []) {
            $errors[] = "{$prefix}.payload_json.aggregate.accounting:accounting section is required for post";
        }

        return array_merge($errors, $this->validateAggregateExtras($aggregate, $prefix));
    }

    /** @param array<string, mixed> $aggregate @return list<string> */
    protected function validateAggregateExtras(array $aggregate, string $prefix): array
    {
        $errors = [];
        $header = is_array($aggregate['header'] ?? null) ? $aggregate['header'] : [];
        $lines = is_array($aggregate['lines'] ?? null) ? $aggregate['lines'] : [];

        if (array_key_exists('created_by_user_id', $header)
            && !Uuid::isValid((string) $header['created_by_user_id'])) {
            $errors[] = "{$prefix}.payload_json.aggregate.header.created_by_user_id:Invalid UUID";
        }

        foreach ($lines as $lineIndex => $line) {
            if (!is_array($line)) {
                $errors[] = "{$prefix}.payload_json.aggregate.lines.{$lineIndex}:Line must be an object";
                continue;
            }
            $lineId = (string) ($line['line_id'] ?? $line['id'] ?? '');
            if ($lineId === '' || !Uuid::isValid($lineId)) {
                $errors[] = "{$prefix}.payload_json.aggregate.lines.{$lineIndex}.line_id:Valid line id required";
            }
            $productId = (string) ($line['product_id'] ?? '');
            if ($productId === '' || !Uuid::isValid($productId)) {
                $errors[] = "{$prefix}.payload_json.aggregate.lines.{$lineIndex}.product_id:Valid product_id required";
            }
            $quantity = (float) ($line['quantity'] ?? 0);
            if ($quantity <= 0) {
                $errors[] = "{$prefix}.payload_json.aggregate.lines.{$lineIndex}.quantity:Quantity must be > 0";
            }
        }

        return $errors;
    }
}
