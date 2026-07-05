<?php

declare(strict_types=1);

namespace MizaCloud\Core\Middleware;

use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Http\Response;

/**
 * يضيف X-Request-ID إن لم يُرسَل من العميل.
 */
final class RequestIdMiddleware implements MiddlewareInterface
{
    public function handle(Request $request, callable $next): Response
    {
        $requestId = $request->headers['X-Request-ID']
            ?? $request->headers['x-request-id']
            ?? $this->generateId();

        $request = $request->withAttribute('request_id', $requestId);
        $response = $next($request);

        // Response headers enrichment — لاحقاً عند ربط Response mutable.
        return $response;
    }

    private function generateId(): string
    {
        return bin2hex(random_bytes(16));
    }
}
