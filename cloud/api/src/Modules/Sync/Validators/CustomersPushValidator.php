<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Validators;

final class CustomersPushValidator extends CatalogPartnerPushValidator
{
    protected function entityType(): string
    {
        return 'customer';
    }

    protected function entityLabel(): string
    {
        return 'Customer';
    }
}
