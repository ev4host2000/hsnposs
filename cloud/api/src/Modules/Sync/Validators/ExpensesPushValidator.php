<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Validators;

use MizaCloud\Modules\Auth\Support\Uuid;

final class ExpensesPushValidator extends SyncValidator
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

        if (($event['entity_type'] ?? '') !== 'expense') {
            $errors[] = "{$prefix}.entity_type:Only expense entity_type is supported";
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

        if ($operation === 'delete') {
            return $errors;
        }

        $payload = $event['payload_json'] ?? null;
        if (!is_array($payload)) {
            $errors[] = "{$prefix}.payload_json:Payload is required";

            return $errors;
        }

        if (!is_string($payload['title'] ?? null) || trim((string) $payload['title']) === '') {
            $errors[] = "{$prefix}.payload_json.title:title is required";
        }

        if (!isset($payload['amount']) || !is_numeric($payload['amount'])) {
            $errors[] = "{$prefix}.payload_json.amount:amount is required";
        } elseif ((float) $payload['amount'] <= 0) {
            $errors[] = "{$prefix}.payload_json.amount:amount must be greater than zero";
        }

        if (!is_string($payload['expense_date'] ?? null) || trim((string) $payload['expense_date']) === '') {
            $errors[] = "{$prefix}.payload_json.expense_date:expense_date is required";
        }

        $createdBy = $payload['created_by_user_id'] ?? null;
        if (!is_string($createdBy) || !Uuid::isValid($createdBy)) {
            $errors[] = "{$prefix}.payload_json.created_by_user_id:Valid created_by_user_id UUID is required";
        }

        return $errors;
    }
}
