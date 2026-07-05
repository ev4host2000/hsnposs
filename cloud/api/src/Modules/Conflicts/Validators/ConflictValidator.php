<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Conflicts\Validators;

use MizaCloud\Core\Helpers\Validator;

final class ConflictValidator extends Validator
{
    public function __construct(private readonly array $payload) {}
}
