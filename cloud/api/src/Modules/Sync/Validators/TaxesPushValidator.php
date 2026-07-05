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
        if (!isset($payload['percent']) || !is_numeric($payload['percent'])) {
            return ["{$prefix}.payload_json.percent:Tax percent is required"];
        }

        return [];
    }
}
