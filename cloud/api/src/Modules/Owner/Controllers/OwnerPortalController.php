<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Owner\Controllers;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Core\Http\Controller;
use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Http\Response;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Modules\Owner\Services\OwnerPortalService;

final class OwnerPortalController extends Controller
{
    public function __construct(
        ResponseBuilder $responses,
        private readonly OwnerPortalService $service,
    ) {
        parent::__construct($responses);
    }

    public function login(Request $request): Response
    {
        $data = $this->service->login($this->jsonBody($request));

        return $this->responses->success($data);
    }

    public function me(Request $request): Response
    {
        $data = $this->service->me($request);

        return $this->responses->success($data);
    }

    public function dashboard(Request $request): Response
    {
        $data = $this->service->dashboard($request);

        return $this->responses->success($data);
    }

    public function devices(Request $request): Response
    {
        $data = $this->service->devices($request);

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
