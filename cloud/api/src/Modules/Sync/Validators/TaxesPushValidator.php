<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Validators;

final class TaxesPushValidator extends CatalogNamedEntityPushValidator
{
    protected function entityType(): string
    {
        return 'tax';
    }

    protected function entityLabel(): string
    {
        return 'Tax';
    }

    /** @param array<string, mixed>|null $payload @return list<string> */
    protected function validatePayload(?array $payload, string $prefix): array
    {
        if ($payload === null) {
            return [];
        }
        // Tax nature: percent must be numeric when present.
        // Native patch may omit unchanged percent (Update Contract v2).
        if (!array_key_exists('percent', $payload)) {
            return [];
        }
        if (!is_numeric($payload['percent'])) {
            return ["{$prefix}.payload_json.percent:Tax percent must be numeric"];
        }

        return [];
    }
}
