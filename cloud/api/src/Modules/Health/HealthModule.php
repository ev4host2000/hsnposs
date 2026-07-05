<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Health;

use MizaCloud\Core\Config\Config;
use MizaCloud\Core\Container\Container;
use MizaCloud\Core\Database\DatabaseManager;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Core\Logging\Logger;
use MizaCloud\Core\Modules\ModuleInterface;
use MizaCloud\Core\Router\Router;
use MizaCloud\Modules\Health\Controllers\HealthController;
use MizaCloud\Modules\Health\Repositories\HealthRepository;
use MizaCloud\Modules\Health\Services\HealthService;

final class HealthModule implements ModuleInterface
{
    public function name(): string
    {
        return 'health';
    }

    public function register(Container $container): void
    {
        $container->singleton(HealthRepository::class, static fn ($c) => new HealthRepository(
            $c->get(DatabaseManager::class),
        ));

        $container->singleton(HealthService::class, static fn ($c) => new HealthService(
            $c->get(HealthRepository::class),
            $c->get(Config::class),
            $c->get(Logger::class),
        ));

        $container->singleton(HealthController::class, static fn ($c) => new HealthController(
            $c->get(ResponseBuilder::class),
            $c->get(HealthService::class),
        ));
    }

    public function routes(Router $router): void
    {
        $controller = HealthController::class;

        foreach ($this->routePrefixes() as $prefix) {
            $router->get("{$prefix}", [$controller, 'index']);
            $router->get("{$prefix}/ping", [$controller, 'ping']);
            $router->get("{$prefix}/version", [$controller, 'version']);
            $router->get("{$prefix}/database", [$controller, 'database']);
            $router->get("{$prefix}/time", [$controller, 'time']);
        }
    }

    /** @return list<string> */
    private function routePrefixes(): array
    {
        return ['/health', '/v1/health'];
    }
}
