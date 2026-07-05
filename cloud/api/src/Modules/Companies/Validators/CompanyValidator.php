<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Companies\Validators;

use MizaCloud\Core\Helpers\Validator;

final class CompanyValidator extends Validator
{
    public function __construct(private readonly array $payload) {}
}
