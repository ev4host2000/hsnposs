<?php

declare(strict_types=1);

namespace MizaCloud\Core\Middleware;

use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Http\Response;

/**
 * سلسلة Middleware — تُنفَّذ قبل Router dispatch.
 */
final class MiddlewarePipeline
{
    /** @var list<MiddlewareInterface> */
    private array $middleware = [];

    public function add(MiddlewareInterface $middleware): void
    {
        $this->middleware[] = $middleware;
    }

    public function process(Request $request, callable $destination): Response
    {
        $pipeline = array_reduce(
            array_reverse($this->middleware),
            static function (callable $next, MiddlewareInterface $mw): callable {
                return static fn (Request $req): Response => $mw->handle($req, $next);
            },
            $destination,
        );

        return $pipeline($request);
    }
}
