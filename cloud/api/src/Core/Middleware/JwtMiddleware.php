<?php

declare(strict_types=1);

namespace MizaCloud\Core\Middleware;

use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Http\Response;

/**
 * JWT Middleware — هيكل فقط.
 * التحقق من التوقيع والـ scopes يُضاف في Phase لاحقة (بدون منطق هنا).
 */
final class JwtMiddleware implements MiddlewareInterface
{
    public function __construct(
        private readonly array $jwtConfig,
        private readonly bool $required = true,
    ) {}

    public function handle(Request $request, callable $next): Response
    {
        // Phase لاحقة: استخراج Bearer، validate، حقن claims في Request attributes.
        // حالياً: يمرّر الطلب دون تعديل عند عدم تفعيل التحقق.
        if (!$this->required) {
            return $next($request);
        }

        $authorization = $request->headers['Authorization']
            ?? $request->headers['authorization']
            ?? '';

        if ($authorization === '' && $this->required) {
            // Phase لاحقة: return 401 via ResponseBuilder
        }

        return $next($request);
    }
}
