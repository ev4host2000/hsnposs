<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Branches\Validators;

use MizaCloud\Core\Helpers\Validator;

final class BranchValidator extends Validator
{
    public function __construct(private readonly array $payload) {}
}
