<?php

declare(strict_types=1);

namespace MizaCloud\Core\Middleware;

use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Http\Response;

/**
 * CORS headers — إعدادات فقط، بدون منطق أعمال.
 */
final class CorsMiddleware implements MiddlewareInterface
{
    public function __construct(
        private readonly array $allowedOrigins = ['*'],
        private readonly array $allowedMethods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    ) {}

    public function handle(Request $request, callable $next): Response
    {
        if ($request->method === 'OPTIONS') {
            return new Response(204, '');
        }
        return $next($request);
    }
}
