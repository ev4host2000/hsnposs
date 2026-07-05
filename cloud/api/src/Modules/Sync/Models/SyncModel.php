<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Models;

final class SyncModel
{
    public function __construct(public readonly string $id = '') {}
}
