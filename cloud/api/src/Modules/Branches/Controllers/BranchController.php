<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Branches\Controllers;

use MizaCloud\Core\Http\Controller;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Modules\Branches\Services\BranchService;

final class BranchController extends Controller
{
    public function __construct(ResponseBuilder $responses, private readonly BranchService $service)
    {
        parent::__construct($responses);
    }
}
