<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Owner\Support;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Core\Http\Request;
use MizaCloud\Modules\Auth\Repositories\AuthRepository;
use MizaCloud\Modules\Auth\Services\JwtService;
use MizaCloud\Modules\Auth\Support\TokenHasher;

final class OwnerPortalBearer
{
    public function __construct(
        private readonly JwtService $jwt,
        private readonly AuthRepository $authRepository,
    ) {}

    /** @return array<string, mixed> */
    public function authenticate(Request $request): array
    {
        $token = $this->extract($request);
        if ($token === null) {
            throw new HttpException('unauthorized', 'Authorization required', 401);
        }

        $claims = $this->jwt->decode($token);
        if (($claims['token_type'] ?? '') !== 'owner_portal') {
            throw new HttpException('forbidden', 'Owner portal token required', 403);
        }

        $stored = $this->authRepository->findApiTokenByHash(TokenHasher::hash($token));
        if ($stored === null || $stored['revoked_at'] !== null) {
            throw new HttpException('unauthorized', 'Access token revoked', 401);
        }

        return $claims;
    }

    public function extract(Request $request): ?string
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

        if (preg_match('/^Bearer\s+(\S+)$/i', $authorization, $matches) !== 1) {
            return null;
        }

        return $matches[1];
    }
}
