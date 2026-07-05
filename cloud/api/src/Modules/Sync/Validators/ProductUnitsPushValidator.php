<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Validators;

final class ProductUnitsPushValidator extends CatalogNamedEntityPushValidator
{
    protected function entityType(): string
    {
        return 'product_unit';
    }

    protected function entityLabel(): string
    {
        return 'Unit';
    }
}
