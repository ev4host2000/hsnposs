<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Controllers;

use MizaCloud\Core\Http\Controller;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Modules\Sync\Services\SyncService;

final class SyncController extends Controller
{
    public function __construct(ResponseBuilder $responses, private readonly SyncService $service)
    {
        parent::__construct($responses);
    }
}
