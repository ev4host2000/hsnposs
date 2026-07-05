<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Notifications\Controllers;

use MizaCloud\Core\Http\Controller;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Modules\Notifications\Services\NotificationService;

final class NotificationController extends Controller
{
    public function __construct(ResponseBuilder $responses, private readonly NotificationService $service)
    {
        parent::__construct($responses);
    }
}
