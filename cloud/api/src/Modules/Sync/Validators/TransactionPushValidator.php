<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Validators;

use MizaCloud\Modules\Auth\Support\Uuid;

abstract class TransactionPushValidator extends SyncValidator
{
    private const MAX_EVENTS = 50;

    /** @param array<string, mixed> $payload */
    public function __construct(private readonly array $payload) {}

    abstract protected function entityType(): string;

    abstract protected function entityLabel(): string;

    /** @return list<string> */
    protected function errors(): array
    {
        $errors = [];

        foreach ([
            $this->requireUuid($this->payload, 'company_id', 'Company ID'),
            $this->requireUuid($this->payload, 'branch_id', 'Branch ID'),
            $this->requireUuid($this->payload, 'device_id', 'Device ID'),
            $this->requireUuid($this->payload, 'batch_id', 'Batch ID'),
        ] as $error) {
            if ($error !== null) {
                $errors[] = $error;
            }
        }

        $events = $this->payload['events'] ?? null;
        if (!is_array($events)) {
            $errors[] = 'events:Events array is required';

            return $errors;
        }
        if ($events === []) {
            $errors[] = 'events:At least one event is required';
        }
        if (count($events) > self::MAX_EVENTS) {
            $errors[] = 'events:Batch too large (max ' . self::MAX_EVENTS . ')';
        }

        foreach ($events as $index => $event) {
            if (!is_array($event)) {
                $errors[] = "events:Event {$index} must be an object";
                continue;
            }
            $errors = array_merge($errors, $this->validateEvent($event, $index));
        }

        return $errors;
    }

    /** @param array<string, mixed> $event @return list<string> */
    protected function validateEvent(array $event, int $index): array
    {
        $errors = [];
        $prefix = "events.{$index}";
        $entityType = $this->entityType();

        if (($event['entity_type'] ?? '') !== $entityType) {
            $errors[] = "{$prefix}.entity_type:Only {$entityType} entity_type is supported";
        }

        $operation = (string) ($event['operation'] ?? '');
        if (!in_array($operation, $this->supportedPushOperations(), true)) {
            $errors[] = "{$prefix}.operation:Unsupported operation for {$entityType}";
        }

        if (!is_string($event['entity_id'] ?? null) || !Uuid::isValid((string) $event['entity_id'])) {
            $errors[] = "{$prefix}.entity_id:Valid entity_id UUID is required";
        }

        if (!is_string($event['outbox_id'] ?? null) || trim((string) $event['outbox_id']) === '') {
            $errors[] = "{$prefix}.outbox_id:Outbox ID is required";
        }

        if (!is_string($event['idempotency_key'] ?? null) || trim((string) $event['idempotency_key']) === '') {
            $errors[] = "{$prefix}.idempotency_key:Idempotency key is required";
        }

        if ($operation !== 'cancel') {
            $payload = $event['payload_json'] ?? null;
            if (!is_array($payload)) {
                $errors[] = "{$prefix}.payload_json:Payload is required";
            } else {
                $errors = array_merge($errors, $this->validateTransactionPayload($payload, $prefix));
            }
        }

        return $errors;
    }

    /** @param array<string, mixed> $payload @return list<string> */
    protected function validateTransactionPayload(array $payload, string $prefix): array
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

        if (($header['status'] ?? '') !== 'draft') {
            $errors[] = "{$prefix}.payload_json.aggregate.header.status:Only draft status is supported";
        }

        if (!is_string($header['id'] ?? null) || !Uuid::isValid((string) $header['id'])) {
            $errors[] = "{$prefix}.payload_json.aggregate.header.id:Valid header id is required";
        }

        $lines = $aggregate['lines'] ?? null;
        if (!is_array($lines)) {
            $errors[] = "{$prefix}.payload_json.aggregate.lines:lines array is required";
        } elseif ($lines === [] && ($payload['operation'] ?? '') === 'create') {
            $errors[] = "{$prefix}.payload_json.aggregate.lines:At least one line is required for create";
        }

        return array_merge($errors, $this->validateAggregateExtras($aggregate, $prefix));
    }

    /** @return list<string> */
    protected function supportedPushOperations(): array
    {
        return ['create', 'update', 'cancel'];
    }

    /** @param array<string, mixed> $aggregate @return list<string> */
    protected function validateAggregateExtras(array $aggregate, string $prefix): array
    {
        return [];
    }
}
