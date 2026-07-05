<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Catalog\Validators;

use MizaCloud\Core\Helpers\Validator;

final class CatalogValidator extends Validator
{
    public function __construct(private readonly array $payload) {}
}
