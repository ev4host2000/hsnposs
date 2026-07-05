<?php

declare(strict_types=1);

namespace MizaCloud\Core\Router;

use Closure;
use MizaCloud\Core\Container\Container;
use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Http\Response;
use RuntimeException;

/**
 * Router — تسجيل مسارات وتوجيه الطلبات إلى Controllers.
 */
final class Router
{
    /** @var list<Route> */
    private array $routes = [];

    private ?Container $container = null;

    public function setContainer(Container $container): void
    {
        $this->container = $container;
    }

    public function add(
        string $method,
        string $pattern,
        Closure|array|string $handler,
        array $middleware = [],
    ): void {
        $this->routes[] = new Route(
            strtoupper($method),
            $pattern,
            $handler,
            $middleware,
        );
    }

    public function get(string $pattern, Closure|array|string $handler, array $middleware = []): void
    {
        $this->add('GET', $pattern, $handler, $middleware);
    }

    public function post(string $pattern, Closure|array|string $handler, array $middleware = []): void
    {
        $this->add('POST', $pattern, $handler, $middleware);
    }

    public function put(string $pattern, Closure|array|string $handler, array $middleware = []): void
    {
        $this->add('PUT', $pattern, $handler, $middleware);
    }

    public function patch(string $pattern, Closure|array|string $handler, array $middleware = []): void
    {
        $this->add('PATCH', $pattern, $handler, $middleware);
    }

    public function delete(string $pattern, Closure|array|string $handler, array $middleware = []): void
    {
        $this->add('DELETE', $pattern, $handler, $middleware);
    }

    /** @return list<Route> */
    public function routes(): array
    {
        return $this->routes;
    }

    public function dispatch(Request $request): Response
    {
        $path = $this->normalizePath($request->path);

        foreach ($this->routes as $route) {
            if ($route->method !== $request->method) {
                continue;
            }
            $params = $this->match($route->pattern, $path);
            if ($params === null) {
                continue;
            }

            return $this->invokeHandler($route->handler, $request, $params);
        }

        throw new HttpException('not_found', 'Route not found', 404);
    }

    private function normalizePath(string $path): string
    {
        $path = parse_url($path, PHP_URL_PATH) ?: $path;
        $normalized = rtrim($path, '/');

        return $normalized === '' ? '/' : $normalized;
    }

    /** @param array<string, string> $params */
    private function invokeHandler(Closure|array|string $handler, Request $request, array $params): Response
    {
        if ($this->container === null) {
            throw new RuntimeException('Router container not configured');
        }

        $request = $this->injectRouteParams($request, $params);

        if ($handler instanceof Closure) {
            $result = $handler($request, $this->container);
            return $this->assertResponse($result);
        }

        if (is_array($handler) && count($handler) === 2) {
            [$class, $method] = $handler;
            $controller = $this->container->get(is_string($class) ? $class : $class::class);
            if (!is_object($controller) || !method_exists($controller, (string) $method)) {
                throw new HttpException('internal_error', 'Route handler not found', 500);
            }
            $result = $controller->{$method}($request);

            return $this->assertResponse($result);
        }

        if (is_string($handler) && str_contains($handler, '@')) {
            [$class, $method] = explode('@', $handler, 2);
            $controller = $this->container->get($class);
            if (!method_exists($controller, $method)) {
                throw new HttpException('internal_error', 'Route handler not found', 500);
            }
            $result = $controller->{$method}($request);

            return $this->assertResponse($result);
        }

        throw new HttpException('internal_error', 'Invalid route handler', 500);
    }

    /** @param array<string, string> $params */
    private function injectRouteParams(Request $request, array $params): Request
    {
        foreach ($params as $key => $value) {
            $request = $request->withAttribute($key, $value);
        }

        return $request;
    }

    private function assertResponse(mixed $result): Response
    {
        if (!$result instanceof Response) {
            throw new RuntimeException('Route handler must return Response');
        }

        return $result;
    }

    /** @return array<string, string>|null */
    private function match(string $pattern, string $path): ?array
    {
        $regex = preg_replace('#\{([a-zA-Z_]+)\}#', '(?P<$1>[^/]+)', $pattern);
        $regex = '#^' . $regex . '$#';
        if (!is_string($regex) || !preg_match($regex, $path, $matches)) {
            return null;
        }
        $params = [];
        foreach ($matches as $key => $value) {
            if (is_string($key)) {
                $params[$key] = $value;
            }
        }

        return $params;
    }
}
