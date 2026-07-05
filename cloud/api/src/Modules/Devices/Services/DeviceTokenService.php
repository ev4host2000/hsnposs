<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Devices\Services;

use DateTimeImmutable;
use MizaCloud\Modules\Auth\Services\JwtService;
use MizaCloud\Modules\Auth\Support\TokenHasher;
use MizaCloud\Modules\Auth\Support\Uuid;
use MizaCloud\Modules\Devices\Repositories\DeviceRepository;

final class DeviceTokenService
{
    public function __construct(
        private readonly DeviceRepository $repository,
        private readonly JwtService $jwt,
        private readonly int $accessTtl,
        private readonly int $refreshTtl,
    ) {}

    /**
     * @param list<string> $scopes
     * @return array{
     *   session_id: string,
     *   access_token: string,
     *   refresh_token: string,
     *   token_type: string,
     *   expires_in: int,
     *   expires_at: string
     * }
     */
    public function issueDeviceSessionTokens(
        string $deviceId,
        string $companyId,
        string $branchId,
        ?string $userId,
        array $scopes,
        ?string $ipAddress,
        ?string $userAgent,
    ): array {
        $now = new DateTimeImmutable('now');
        $refreshExpires = $now->modify('+' . $this->refreshTtl . ' seconds');
        $accessExpires = $now->modify('+' . $this->accessTtl . ' seconds');

        $sessionId = $this->repository->createDeviceSession(
            $deviceId,
            $companyId,
            $branchId,
            $userId,
            $ipAddress,
            $userAgent,
            $refreshExpires,
        );

        $access = $this->jwt->issueAccessToken(
            $deviceId,
            $sessionId,
            $companyId,
            $branchId,
            $deviceId,
            $scopes,
        );

        $refreshPlain = TokenHasher::refreshToken();
        $this->repository->createApiToken(
            TokenHasher::hash($access['token']),
            'device',
            $deviceId,
            $companyId,
            $sessionId,
            $scopes,
            $accessExpires,
        );
        $this->repository->createRefreshToken(
            TokenHasher::hash($refreshPlain),
            $sessionId,
            $companyId,
            $userId,
            $refreshExpires,
        );

        return [
            'session_id' => $sessionId,
            'access_token' => $access['token'],
            'refresh_token' => $refreshPlain,
            'token_type' => 'Bearer',
            'expires_in' => $access['expires_in'],
            'expires_at' => $access['expires_at'],
        ];
    }
}
