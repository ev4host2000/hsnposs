<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Users\Validators;

use MizaCloud\Core\Helpers\Validator;

final class UserValidator extends Validator
{
    public function __construct(private readonly array $payload) {}
}
