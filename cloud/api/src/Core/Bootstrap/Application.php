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
        $pipeline->add(new RequestIdMiddleware());
        $pipeline->add(new CorsMiddleware());
        $pipeline->add(new JwtMiddleware($jwtConfig, required: false));

        ModuleRegistry::registerAll($container, $router);
        $router->setContainer($container);

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
