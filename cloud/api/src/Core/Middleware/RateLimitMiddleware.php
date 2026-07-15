<?php

declare(strict_types=1);

namespace MizaCloud\Core\Middleware;

use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Http\Response;

/**
 * Fixed-window rate limiter for sensitive public/auth endpoints (B16 / RAP-P1-01).
 * Uses file storage — suitable for single-node staging; replace with Redis for HA.
 */
final class RateLimitMiddleware implements MiddlewareInterface
{
    /** @var list<string> */
    private const LIMITED_PATHS = [
        // Tenant device login / pairing (existing)
        '/auth/login',
        '/v1/auth/login',
        '/auth/login/pairing',
        '/v1/auth/login/pairing',
        // Ops platform login
        '/admin/auth/login',
        '/v1/admin/auth/login',
        // Password reset
        '/auth/password/forgot',
        '/v1/auth/password/forgot',
        // Public beta / voucher
        '/public/beta-signup',
        '/v1/public/beta-signup',
        '/public/voucher/validate',
        '/v1/public/voucher/validate',
    ];

    /** @var list<string> */
    private const FORGOT_PATHS = [
        '/auth/password/forgot',
        '/v1/auth/password/forgot',
    ];

    /**
     * @param list<string> $trustedProxies Exact IPs or CIDR ranges trusted to set forwarding headers
     */
    public function __construct(
        private readonly bool $enabled,
        private readonly int $maxAttempts,
        private readonly int $windowSeconds,
        private readonly string $storagePath,
        private readonly bool $trustProxy = false,
        private readonly array $trustedProxies = [],
        private readonly int $forgotMaxAttempts = 5,
        private readonly int $forgotWindowSeconds = 300,
    ) {}

    public function handle(Request $request, callable $next): Response
    {
        if (!$this->enabled || !in_array($request->path, self::LIMITED_PATHS, true)) {
            return $next($request);
        }

        [$maxAttempts, $windowSeconds] = $this->limitsForPath($request->path);
        $clientKey = $this->clientKey($request);
        $now = time();

        if ($this->isLimited($clientKey, $now, $maxAttempts, $windowSeconds)) {
            return new Response(
                429,
                (string) json_encode([
                    'error' => 'rate_limit_exceeded',
                    'message' => 'Too many login attempts. Try again later.',
                ], JSON_THROW_ON_ERROR),
                [
                    'Content-Type' => 'application/json; charset=utf-8',
                    'Retry-After' => (string) $windowSeconds,
                ],
            );
        }

        $this->recordAttempt($clientKey, $now, $windowSeconds);

        return $next($request);
    }

    /** @return array{0: int, 1: int} [maxAttempts, windowSeconds] */
    private function limitsForPath(string $path): array
    {
        if (in_array($path, self::FORGOT_PATHS, true)) {
            return [$this->forgotMaxAttempts, $this->forgotWindowSeconds];
        }

        return [$this->maxAttempts, $this->windowSeconds];
    }

    private function clientKey(Request $request): string
    {
        $ip = $this->resolveClientIp($request);

        return hash('sha256', $ip . '|' . $request->path);
    }

    private function resolveClientIp(Request $request): string
    {
        $remote = trim((string) ($_SERVER['REMOTE_ADDR'] ?? 'unknown'));
        if ($remote === '') {
            $remote = 'unknown';
        }

        if (!$this->trustProxy || !$this->isTrustedProxy($remote)) {
            return $remote;
        }

        $forwarded = $this->headerValue($request, 'X-Forwarded-For');
        if ($forwarded !== null && $forwarded !== '') {
            if (str_contains($forwarded, ',')) {
                $forwarded = trim(explode(',', $forwarded)[0]);
            }

            return $forwarded !== '' ? $forwarded : $remote;
        }

        $realIp = $this->headerValue($request, 'X-Real-IP');
        if ($realIp !== null && $realIp !== '') {
            return trim($realIp);
        }

        return $remote;
    }

    private function headerValue(Request $request, string $name): ?string
    {
        foreach ($request->headers as $key => $value) {
            if (strcasecmp((string) $key, $name) === 0) {
                return is_string($value) ? $value : null;
            }
        }

        return null;
    }

    private function isTrustedProxy(string $ip): bool
    {
        if ($ip === 'unknown' || $this->trustedProxies === []) {
            return false;
        }

        foreach ($this->trustedProxies as $entry) {
            $entry = trim($entry);
            if ($entry === '') {
                continue;
            }
            if (str_contains($entry, '/')) {
                if ($this->ipInCidr($ip, $entry)) {
                    return true;
                }
                continue;
            }
            if ($ip === $entry) {
                return true;
            }
        }

        return false;
    }

    private function ipInCidr(string $ip, string $cidr): bool
    {
        $parts = explode('/', $cidr, 2);
        if (count($parts) !== 2) {
            return false;
        }

        [$subnet, $maskBits] = $parts;
        $maskBits = (int) $maskBits;
        $ipLong = ip2long($ip);
        $subnetLong = ip2long($subnet);
        if ($ipLong === false || $subnetLong === false || $maskBits < 0 || $maskBits > 32) {
            return false;
        }

        if ($maskBits === 0) {
            return true;
        }

        $mask = -1 << (32 - $maskBits);

        return ($ipLong & $mask) === ($subnetLong & $mask);
    }

    private function isLimited(string $key, int $now, int $maxAttempts, int $windowSeconds): bool
    {
        $data = $this->readBucket($key);
        if ($data === null) {
            return false;
        }

        if ($now - $data['window_start'] >= $windowSeconds) {
            return false;
        }

        return $data['count'] >= $maxAttempts;
    }

    private function recordAttempt(string $key, int $now, int $windowSeconds): void
    {
        $this->ensureStorageDir();
        $file = $this->bucketFile($key);
        $data = $this->readBucket($key);

        if ($data === null || $now - $data['window_start'] >= $windowSeconds) {
            $data = ['window_start' => $now, 'count' => 1];
        } else {
            $data['count']++;
        }

        file_put_contents($file, (string) json_encode($data), LOCK_EX);
    }

    /** @return array{window_start: int, count: int}|null */
    private function readBucket(string $key): ?array
    {
        $file = $this->bucketFile($key);
        if (!is_file($file)) {
            return null;
        }

        $raw = file_get_contents($file);
        if ($raw === false || $raw === '') {
            return null;
        }

        $decoded = json_decode($raw, true);
        if (!is_array($decoded) || !isset($decoded['window_start'], $decoded['count'])) {
            return null;
        }

        return [
            'window_start' => (int) $decoded['window_start'],
            'count' => (int) $decoded['count'],
        ];
    }

    private function bucketFile(string $key): string
    {
        return rtrim($this->storagePath, '/\\') . DIRECTORY_SEPARATOR . $key . '.json';
    }

    private function ensureStorageDir(): void
    {
        if (!is_dir($this->storagePath)) {
            mkdir($this->storagePath, 0755, true);
        }
    }
}
