<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Conflicts\Services;

use MizaCloud\Modules\Conflicts\Repositories\ConflictRepository;

final class ConflictService
{
    public function __construct(private readonly ConflictRepository $repository) {}
}
