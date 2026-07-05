<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Validators;

final class PriceListsPushValidator extends CatalogNamedEntityPushValidator
{
    protected function entityType(): string
    {
        return 'price_list';
    }

    protected function entityLabel(): string
    {
        return 'Price list';
    }

    /** @param array<string, mixed>|null $payload @return list<string> */
    protected function validatePayload(?array $payload, string $prefix): array
    {
        if ($payload === null) {
            return [];
        }
        $items = $payload['items'] ?? null;
        if ($items === null) {
            return [];
        }
        if (!is_array($items)) {
            return ["{$prefix}.payload_json.items:Items must be an array"];
        }

        return [];
    }
}
