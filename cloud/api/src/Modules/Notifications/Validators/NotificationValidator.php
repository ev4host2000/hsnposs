<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Notifications\Validators;

use MizaCloud\Core\Helpers\Validator;

final class NotificationValidator extends Validator
{
    public function __construct(private readonly array $payload) {}
}
