<?php

declare(strict_types=1);

namespace MizaCloud\Core\Router;

use Closure;

/**
 * تعريف مسار واحد — Controller يُسجَّل لاحقاً من كل Module.
 */
final class Route
{
    public function __construct(
        public readonly string $method,
        public readonly string $pattern,
        public readonly Closure|array|string $handler,
        public readonly array $middleware = [],
    ) {}
}
