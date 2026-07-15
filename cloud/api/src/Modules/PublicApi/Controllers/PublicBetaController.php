<?php

declare(strict_types=1);

namespace MizaCloud\Modules\PublicApi\Controllers;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Core\Http\Controller;
use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Http\Response;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Modules\PublicApi\Services\PublicBetaService;

final class PublicBetaController extends Controller
{
    public function __construct(
        ResponseBuilder $responses,
        private readonly PublicBetaService $service,
    ) {
        parent::__construct($responses);
    }

    public function signup(Request $request): Response
    {
        $data = $this->service->submitSignup($this->jsonBody($request));

        return $this->responses->success($data, status: 201);
    }

    public function validateVoucher(Request $request): Response
    {
        $data = $this->service->validateVoucher($this->jsonBody($request));

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
