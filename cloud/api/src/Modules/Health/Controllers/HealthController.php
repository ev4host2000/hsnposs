<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Health\Controllers;

use MizaCloud\Core\Http\Controller;
use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Http\Response;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Modules\Health\Services\HealthService;

final class HealthController extends Controller
{
    public function __construct(
        ResponseBuilder $responses,
        private readonly HealthService $service,
    ) {
        parent::__construct($responses);
    }

    public function index(Request $request): Response
    {
        $data = $this->service->summary();
        $status = $data['status'] === 'healthy' ? 200 : 503;

        return $this->responses->success($data, status: $status);
    }

    public function ping(Request $request): Response
    {
        return $this->responses->success($this->service->ping());
    }

    public function version(Request $request): Response
    {
        return $this->responses->success($this->service->version());
    }

    public function database(Request $request): Response
    {
        $data = $this->service->database();
        $status = $data['connected'] ? 200 : 503;

        return $this->responses->success($data, status: $status);
    }

    public function time(Request $request): Response
    {
        return $this->responses->success($this->service->time());
    }
}
