<?php

declare(strict_types=1);

namespace MizaCloud\Core\Middleware;

use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Http\Response;

/**
 * CORS headers — configurable via config/cors.php.
 */
final class CorsMiddleware implements MiddlewareInterface
{
    /** @param list<string> $allowedOrigins */
    /** @param list<string> $allowedMethods */
    /** @param list<string> $allowedHeaders */
    public function __construct(
        private readonly array $allowedOrigins = ['*'],
        private readonly array $allowedMethods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
        private readonly array $allowedHeaders = ['Authorization', 'Content-Type', 'Accept'],
        private readonly int $maxAge = 86400,
        private readonly bool $allowCredentials = false,
    ) {}

    public function handle(Request $request, callable $next): Response
    {
        $origin = $request->headers['Origin'] ?? $request->headers['ORIGIN'] ?? '';

        if ($request->method === 'OPTIONS') {
            return $this->withCorsHeaders(new Response(204, ''), $origin);
        }

        return $this->withCorsHeaders($next($request), $origin);
    }

    private function withCorsHeaders(Response $response, string $origin): Response
    {
        $headers = $response->headers;
        $headers['Access-Control-Allow-Origin'] = $this->resolveOrigin($origin);
        $headers['Access-Control-Allow-Methods'] = implode(', ', $this->allowedMethods);
        $headers['Access-Control-Allow-Headers'] = implode(', ', $this->allowedHeaders);
        $headers['Access-Control-Max-Age'] = (string) $this->maxAge;

        if ($this->allowCredentials && $headers['Access-Control-Allow-Origin'] !== '*') {
            $headers['Access-Control-Allow-Credentials'] = 'true';
        }

        return new Response($response->statusCode, $response->body, $headers);
    }

    private function resolveOrigin(string $origin): string
    {
        if ($origin === '') {
            return $this->allowedOrigins[0] ?? '*';
        }

        if (in_array('*', $this->allowedOrigins, true)) {
            return '*';
        }

        if (in_array($origin, $this->allowedOrigins, true)) {
            return $origin;
        }

        return $this->allowedOrigins[0] ?? '*';
    }
}
