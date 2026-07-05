<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Devices\Controllers;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Core\Http\Controller;
use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Http\Response;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Modules\Devices\Services\DeviceService;

final class DeviceController extends Controller
{
    public function __construct(
        ResponseBuilder $responses,
        private readonly DeviceService $service,
    ) {
        parent::__construct($responses);
    }

    public function register(Request $request): Response
    {
        $result = $this->service->register($this->jsonBody($request), $request);

        return $this->responses->success($result['data'], status: $result['status']);
    }

    public function heartbeat(Request $request): Response
    {
        $data = $this->service->heartbeat($this->jsonBody($request), $request);

        return $this->responses->success($data);
    }

    public function me(Request $request): Response
    {
        $data = $this->service->me($request);

        return $this->responses->success($data);
    }

    /** @return array<string, mixed> */
    private function jsonBody(Request $request): array
    {
        if ($request->body === null || trim($request->body) === '') {
            return [];
        }

        $decoded = json_decode($request->body, true);
        if (!is_array($decoded)) {
            throw new HttpException('validation_error', 'Invalid JSON body', 400);
        }

        return $decoded;
    }
}
