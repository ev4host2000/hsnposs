<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Users\Services;

use MizaCloud\Modules\Users\Repositories\UserRepository;

final class UserService
{
    public function __construct(private readonly UserRepository $repository) {}
}
