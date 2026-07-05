<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Services;

use MizaCloud\Modules\Sync\Repositories\SyncRepository;

final class SyncService
{
    public function __construct(private readonly SyncRepository $repository) {}
}
