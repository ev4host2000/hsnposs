<?php

declare(strict_types=1);

namespace MizaCloud\Core\Bootstrap;

use MizaCloud\Core\Config\Config;
use MizaCloud\Core\Container\Container;
use MizaCloud\Core\Database\Connection;
use MizaCloud\Core\Database\DatabaseManager;
use MizaCloud\Core\Exceptions\ExceptionHandler;
use MizaCloud\Core\Helpers\Env;
use MizaCloud\Core\Helpers\RequestFactory;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Core\Logging\Logger;
use MizaCloud\Core\Middleware\CorsMiddleware;
use MizaCloud\Core\Middleware\JwtMiddleware;
use MizaCloud\Core\Middleware\MiddlewarePipeline;
use MizaCloud\Core\Middleware\RateLimitMiddleware;
use MizaCloud\Core\Middleware\RequestIdMiddleware;
use MizaCloud\Core\Modules\ModuleRegistry;
use MizaCloud\Core\Router\Router;
use Throwable;

/**
 * تطبيق Miza Cloud — Bootstrap + HTTP lifecycle.
 */
final class Application
{
    private function __construct(
        private readonly Container $container,
        private readonly Router $router,
        private readonly MiddlewarePipeline $middleware,
        private readonly ExceptionHandler $exceptions,
    ) {}

    public static function create(string $basePath): self
    {
        Env::load($basePath);

        $container = new Container();
        $config = Config::loadFromPath($basePath . '/config');
        $container->instance(Config::class, $config);

        $logConfig = $config->get('logging', []);
        $logger = new Logger(
            $basePath . '/' . ($logConfig['path'] ?? 'storage/logs'),
            (string) ($logConfig['level'] ?? 'info'),
        );
        $container->instance(Logger::class, $logger);

        $responses = new ResponseBuilder();
        $container->instance(ResponseBuilder::class, $responses);

        $appConfig = $config->get('app', []);
        $debug = (bool) ($appConfig['debug'] ?? false);
        $handler = new ExceptionHandler($responses, $logger, $debug);
        $container->instance(ExceptionHandler::class, $handler);

        $dbConfig = $config->get('database', []);
        if (!is_array($dbConfig)) {
            $dbConfig = [];
        }
        $connection = new Connection($dbConfig);
        $container->singleton(Connection::class, static fn () => $connection);
        $container->singleton(DatabaseManager::class, static fn (Container $c) => new DatabaseManager($c->get(Connection::class)));

        $jwtConfig = $config->get('jwt', []);
        if (!is_array($jwtConfig)) {
            $jwtConfig = [];
        }

        $router = new Router();
        $container->instance(Router::class, $router);

        $pipeline = new MiddlewarePipeline();

        $corsConfig = $config->get('cors', []);
        if (!is_array($corsConfig)) {
            $corsConfig = [];
        }

        $rateLimitConfig = $config->get('rate_limit', []);
        if (!is_array($rateLimitConfig)) {
            $rateLimitConfig = [];
        }

        $pipeline->add(new RequestIdMiddleware());
        $pipeline->add(new CorsMiddleware(
            allowedOrigins: $corsConfig['allowed_origins'] ?? ['*'],
            allowedMethods: $corsConfig['allowed_methods'] ?? ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
            allowedHeaders: $corsConfig['allowed_headers'] ?? ['Authorization', 'Content-Type', 'Accept'],
            maxAge: (int) ($corsConfig['max_age'] ?? 86400),
            allowCredentials: (bool) ($corsConfig['allow_credentials'] ?? false),
        ));
        $pipeline->add(new RateLimitMiddleware(
            enabled: (bool) ($rateLimitConfig['enabled'] ?? true),
            maxAttempts: (int) ($rateLimitConfig['login_max_attempts'] ?? 10),
            windowSeconds: (int) ($rateLimitConfig['login_window_seconds'] ?? 60),
            storagePath: $basePath . '/' . ($rateLimitConfig['storage_path'] ?? 'storage/rate_limit'),
            trustProxy: (bool) ($rateLimitConfig['trust_proxy'] ?? true),
            trustedProxies: is_array($rateLimitConfig['trusted_proxies'] ?? null)
                ? array_values(array_filter(array_map('strval', $rateLimitConfig['trusted_proxies'])))
                : ['127.0.0.1', '::1', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'],
            forgotMaxAttempts: (int) ($rateLimitConfig['forgot_max_attempts'] ?? 5),
            forgotWindowSeconds: (int) ($rateLimitConfig['forgot_window_seconds'] ?? 300),
        ));
        $pipeline->add(new JwtMiddleware($jwtConfig, required: false));

        ModuleRegistry::registerAll($container, $router);
        $router->setContainer($container);

        // Eager-init Ops Audit writer so Auth/Sync can emit events without Admin first hit
        if ($container->has(\MizaCloud\Modules\Admin\Services\OpsAuditWriter::class)) {
            $container->get(\MizaCloud\Modules\Admin\Services\OpsAuditWriter::class);
        }

        $apiRoutes = $basePath . '/routes/api.php';
        if (is_file($apiRoutes)) {
            require $apiRoutes;
        }

        return new self($container, $router, $pipeline, $handler);
    }

    public function run(): void
    {
        $request = RequestFactory::fromGlobals();

        try {
            $response = $this->middleware->process(
                $request,
                fn ($req) => $this->router->dispatch($req),
            );
            $response->send();
        } catch (Throwable $e) {
            $this->exceptions->handle($e, $request)->send();
        }
    }

    public function container(): Container
    {
        return $this->container;
    }
}
