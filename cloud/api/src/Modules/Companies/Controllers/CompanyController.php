<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Companies\Controllers;

use MizaCloud\Core\Http\Controller;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Modules\Companies\Services\CompanyService;

final class CompanyController extends Controller
{
    public function __construct(ResponseBuilder $responses, private readonly CompanyService $service)
    {
        parent::__construct($responses);
    }
}
