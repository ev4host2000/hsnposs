<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Sync\Controllers;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Core\Http\Controller;
use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Http\Response;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Modules\Sync\Services\ProductsSyncService;

final class ProductsSyncController extends Controller
{
    public function __construct(
        ResponseBuilder $responses,
        private readonly ProductsSyncService $service,
    ) {
        parent::__construct($responses);
    }

    public function pushProducts(Request $request): Response
    {
        $result = $this->service->pushProducts($this->jsonBody($request), $request);

        return $this->responses->success($result['data'], status: $result['status']);
    }

    public function pullProducts(Request $request): Response
    {
        $result = $this->service->pullProducts($request);

        return $this->responses->success($result['data'], meta: $result['meta']);
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
