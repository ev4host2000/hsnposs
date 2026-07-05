<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Validators;

use MizaCloud\Modules\Auth\Support\Uuid;

final class ProductsPushValidator extends SyncValidator
{
    private const MAX_EVENTS = 50;

    /** @param array<string, mixed> $payload */
    public function __construct(private readonly array $payload) {}

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
    private function validateEvent(array $event, int $index): array
    {
        $errors = [];
        $prefix = "events.{$index}";

        if (($event['entity_type'] ?? '') !== 'product') {
            $errors[] = "{$prefix}.entity_type:Only product entity_type is supported";
        }

        $operation = (string) ($event['operation'] ?? '');
        if (!in_array($operation, ['create', 'update', 'delete'], true)) {
            $errors[] = "{$prefix}.operation:Invalid operation";
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

        if ($operation !== 'delete') {
            $payload = $event['payload_json'] ?? null;
            if (!is_array($payload)) {
                $errors[] = "{$prefix}.payload_json:Payload is required";
            } elseif (!is_string($payload['name'] ?? null) || trim((string) $payload['name']) === '') {
                $errors[] = "{$prefix}.payload_json.name:Product name is required";
            }
        }

        return $errors;
    }
}
