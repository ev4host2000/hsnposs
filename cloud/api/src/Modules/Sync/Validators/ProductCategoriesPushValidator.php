<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Validators;

final class ProductCategoriesPushValidator extends CatalogNamedEntityPushValidator
{
    protected function entityType(): string
    {
        return 'product_category';
    }

    protected function entityLabel(): string
    {
        return 'Category';
    }
}
