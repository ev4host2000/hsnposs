<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Conflicts\Controllers;

use MizaCloud\Core\Http\Controller;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Modules\Conflicts\Services\ConflictService;

final class ConflictController extends Controller
{
    public function __construct(ResponseBuilder $responses, private readonly ConflictService $service)
    {
        parent::__construct($responses);
    }
}
