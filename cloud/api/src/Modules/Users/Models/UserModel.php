<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Users\Models;

final class UserModel
{
    public function __construct(public readonly string $id = '') {}
}
