<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Branches\Services;

use MizaCloud\Modules\Branches\Repositories\BranchRepository;

final class BranchService
{
    public function __construct(private readonly BranchRepository $repository) {}
}
