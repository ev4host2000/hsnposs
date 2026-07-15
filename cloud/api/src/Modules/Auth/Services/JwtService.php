<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Auth\Services;

use MizaCloud\Core\Exceptions\HttpException;

/**
 * JWT HS256 — بدون تبعيات خارجية.
 */
final class JwtService
{
    public function __construct(
        private readonly string $secret,
        private readonly string $issuer,
        private readonly int $accessTtl,
    ) {
        if ($this->secret === '') {
            throw new \RuntimeException('JWT_SECRET is not configured');
        }
    }

    /**
     * @param list<string> $scopes
     * @return array{token: string, jti: string, expires_at: string, expires_in: int}
     */
    public function issueAccessToken(
        string $userId,
        string $sessionId,
        string $companyId,
        string $branchId,
        string $deviceId,
        array $scopes,
    ): array {
        $issuedAt = time();
        $expiresIn = $this->accessTtl;
        $jti = \MizaCloud\Modules\Auth\Support\Uuid::v4();

        $claims = [
            'iss' => $this->issuer,
            'sub' => $userId,
            'jti' => $jti,
            'iat' => $issuedAt,
            'exp' => $issuedAt + $expiresIn,
            'session_id' => $sessionId,
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'device_id' => $deviceId,
            'scopes' => array_values($scopes),
        ];

        return [
            'token' => $this->encode($claims),
            'jti' => $jti,
            'expires_at' => gmdate('Y-m-d\TH:i:s.v\Z', $claims['exp']),
            'expires_in' => $expiresIn,
        ];
    }

    /**
     * @param list<string> $scopes
     * @return array{token: string, jti: string, expires_at: string, expires_in: int}
     */
    public function issuePlatformAdminToken(array $scopes, int $ttlSeconds): array
    {
        $issuedAt = time();
        $expiresIn = max(60, $ttlSeconds);
        $jti = \MizaCloud\Modules\Auth\Support\Uuid::v4();

        $claims = [
            'iss' => $this->issuer,
            'sub' => 'platform_admin',
            'jti' => $jti,
            'iat' => $issuedAt,
            'exp' => $issuedAt + $expiresIn,
            'token_type' => 'platform_admin',
            'scopes' => array_values($scopes),
        ];

        return [
            'token' => $this->encode($claims),
            'jti' => $jti,
            'expires_at' => gmdate('Y-m-d\TH:i:s.v\Z', $claims['exp']),
            'expires_in' => $expiresIn,
        ];
    }

    /**
     * @param list<string> $scopes
     * @return array{token: string, jti: string, expires_at: string, expires_in: int}
     */
    public function issueOwnerPortalToken(
        string $userId,
        string $companyId,
        string $branchId,
        array $scopes,
        int $ttlSeconds,
    ): array {
        $issuedAt = time();
        $expiresIn = max(300, $ttlSeconds);
        $jti = \MizaCloud\Modules\Auth\Support\Uuid::v4();

        $claims = [
            'iss' => $this->issuer,
            'sub' => $userId,
            'jti' => $jti,
            'iat' => $issuedAt,
            'exp' => $issuedAt + $expiresIn,
            'token_type' => 'owner_portal',
            'company_id' => $companyId,
            'branch_id' => $branchId,
            'device_id' => '',
            'scopes' => array_values($scopes),
        ];

        return [
            'token' => $this->encode($claims),
            'jti' => $jti,
            'expires_at' => gmdate('Y-m-d\TH:i:s.v\Z', $claims['exp']),
            'expires_in' => $expiresIn,
        ];
    }

    /** @return array<string, mixed> */
    public function decode(string $token): array
    {
        $parts = explode('.', $token);
        if (count($parts) !== 3) {
            throw new HttpException('unauthorized', 'Invalid access token', 401);
        }

        [$headerB64, $payloadB64, $signatureB64] = $parts;
        $expected = $this->base64UrlEncode(
            hash_hmac('sha256', "{$headerB64}.{$payloadB64}", $this->secret, true),
        );

        if (!hash_equals($expected, $signatureB64)) {
            throw new HttpException('unauthorized', 'Invalid access token signature', 401);
        }

        $claims = json_decode($this->base64UrlDecode($payloadB64), true);
        if (!is_array($claims)) {
            throw new HttpException('unauthorized', 'Invalid access token payload', 401);
        }

        if (isset($claims['exp']) && time() >= (int) $claims['exp']) {
            throw new HttpException('token_expired', 'Access token expired', 401);
        }

        return $claims;
    }

    /** @param array<string, mixed> $claims */
    private function encode(array $claims): string
    {
        $header = $this->base64UrlEncode(json_encode(['alg' => 'HS256', 'typ' => 'JWT'], JSON_THROW_ON_ERROR));
        $payload = $this->base64UrlEncode(json_encode($claims, JSON_THROW_ON_ERROR));
        $signature = $this->base64UrlEncode(
            hash_hmac('sha256', "{$header}.{$payload}", $this->secret, true),
        );

        return "{$header}.{$payload}.{$signature}";
    }

    private function base64UrlEncode(string $data): string
    {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }

    private function base64UrlDecode(string $data): string
    {
        $remainder = strlen($data) % 4;
        if ($remainder > 0) {
            $data .= str_repeat('=', 4 - $remainder);
        }

        $decoded = base64_decode(strtr($data, '-_', '+/'), true);
        if ($decoded === false) {
            throw new HttpException('unauthorized', 'Invalid access token encoding', 401);
        }

        return $decoded;
    }
}
