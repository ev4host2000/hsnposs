<?php

declare(strict_types=1);

namespace MizaCloud\Core\Middleware;

use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Http\Response;

interface MiddlewareInterface
{
    public function handle(Request $request, callable $next): Response;
}
