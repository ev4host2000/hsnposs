<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Admin\Support;

use MizaCloud\Core\Http\Request;

/**
 * Extract request context for audit rows without touching business logic.
 */
final class OpsAuditContext
{
    public static function clientIp(Request $request): ?string
    {
        $forwarded = $request->headers['X-Forwarded-For'] ?? $request->headers['x-forwarded-for'] ?? null;
        if (is_string($forwarded) && trim($forwarded) !== '') {
            $parts = explode(',', $forwarded);

            return trim($parts[0]);
        }

        $remote = $_SERVER['REMOTE_ADDR'] ?? null;

        return is_string($remote) && $remote !== '' ? $remote : null;
    }

    public static function userAgent(Request $request): ?string
    {
        $ua = $request->headers['User-Agent'] ?? $request->headers['user-agent'] ?? null;

        return is_string($ua) && $ua !== '' ? $ua : null;
    }

    public static function requestId(Request $request): ?string
    {
        $id = $request->headers['X-Request-Id']
            ?? $request->headers['x-request-id']
            ?? $request->attribute('request_id');

        return is_string($id) && $id !== '' ? $id : null;
    }

    /**
     * @param array<string, mixed> $extra
     * @return array<string, mixed>
     */
    public static function fromRequest(Request $request, array $extra = []): array
    {
        return array_merge([
            'ip_address' => self::clientIp($request),
            'user_agent' => self::userAgent($request),
            'request_id' => self::requestId($request),
            'correlation_id' => self::requestId($request),
            'platform' => 'cloud_api',
            'trigger_source' => 'api',
        ], $extra);
    }
}
