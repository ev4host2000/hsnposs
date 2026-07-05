<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Validators;

final class SuppliersPushValidator extends CatalogPartnerPushValidator
{
    protected function entityType(): string
    {
        return 'supplier';
    }

    protected function entityLabel(): string
    {
        return 'Supplier';
    }
}
