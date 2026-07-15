<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Auth\Controllers;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Core\Http\Controller;
use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Http\Response;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Modules\Auth\Services\AuthService;

final class AuthController extends Controller
{
    public function __construct(
        ResponseBuilder $responses,
        private readonly AuthService $service,
    ) {
        parent::__construct($responses);
    }

    public function login(Request $request): Response
    {
        $data = $this->service->login($this->jsonBody($request), $request);

        return $this->responses->success($data);
    }

    public function forgotPassword(Request $request): Response
    {
        $data = $this->service->forgotPassword($this->jsonBody($request));

        return $this->responses->success($data);
    }

    public function loginPairing(Request $request): Response
    {
        $data = $this->service->loginPairing($this->jsonBody($request), $request);

        return $this->responses->success($data);
    }

    public function refresh(Request $request): Response
    {
        $data = $this->service->refresh($this->jsonBody($request));

        return $this->responses->success($data);
    }

    public function logout(Request $request): Response
    {
        $token = $this->bearerToken($request);
        if ($token === null) {
            throw new HttpException('unauthorized', 'Authorization required', 401);
        }

        $data = $this->service->logout($token, $this->jsonBody($request));

        return $this->responses->success($data);
    }

    public function me(Request $request): Response
    {
        $token = $this->bearerToken($request);
        if ($token === null) {
            throw new HttpException('unauthorized', 'Authorization required', 401);
        }

        $data = $this->service->me($token);

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

    private function bearerToken(Request $request): ?string
    {
        $authorization = $request->headers['Authorization']
            ?? $request->headers['authorization']
            ?? '';

        if ($authorization === '' && function_exists('getallheaders')) {
            $headers = getallheaders();
            if (is_array($headers)) {
                foreach ($headers as $name => $value) {
                    if (strcasecmp((string) $name, 'Authorization') === 0 && is_string($value)) {
                        $authorization = $value;
                        break;
                    }
                }
            }
        }

        if ($authorization === '') {
            $authorization = $_SERVER['HTTP_AUTHORIZATION']
                ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
                ?? '';
        }

        if (preg_match('/^Bearer\s+(\S+)$/i', $authorization, $matches) !== 1) {
            return null;
        }

        return $matches[1];
    }
}
