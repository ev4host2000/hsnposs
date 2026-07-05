<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Users\Controllers;

use MizaCloud\Core\Http\Controller;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Modules\Users\Services\UserService;

final class UserController extends Controller
{
    public function __construct(ResponseBuilder $responses, private readonly UserService $service)
    {
        parent::__construct($responses);
    }
}
