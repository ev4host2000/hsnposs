<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Owner;

use MizaCloud\Core\Container\Container;
use MizaCloud\Core\Database\Connection;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Core\Modules\ModuleInterface;
use MizaCloud\Core\Router\Router;
use MizaCloud\Modules\Auth\Repositories\AuthRepository;
use MizaCloud\Modules\Auth\Services\JwtService;
use MizaCloud\Modules\Auth\Services\RoleScopeResolver;
use MizaCloud\Modules\Owner\Controllers\OwnerPortalController;
use MizaCloud\Modules\Owner\Repositories\OwnerDashboardRepository;
use MizaCloud\Modules\Owner\Services\OwnerPortalService;
use MizaCloud\Modules\Owner\Support\OwnerPortalBearer;
use MizaCloud\Core\Config\Config;

final class OwnerModule implements ModuleInterface
{
    public function name(): string
    {
        return 'owner';
    }

    public function register(Container $container): void
    {
        $container->singleton(OwnerDashboardRepository::class, static fn ($c) => new OwnerDashboardRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(OwnerPortalBearer::class, static fn ($c) => new OwnerPortalBearer(
            $c->get(JwtService::class),
            $c->get(AuthRepository::class),
        ));

        $container->singleton(OwnerPortalService::class, static fn ($c) => new OwnerPortalService(
            repository: $c->get(OwnerDashboardRepository::class),
            bearer: $c->get(OwnerPortalBearer::class),
            authRepository: $c->get(AuthRepository::class),
            jwt: $c->get(JwtService::class),
            scopes: $c->get(RoleScopeResolver::class),
            config: $c->get(Config::class),
        ));

        $container->singleton(OwnerPortalController::class, static fn ($c) => new OwnerPortalController(
            $c->get(ResponseBuilder::class),
            $c->get(OwnerPortalService::class),
        ));
    }

    public function routes(Router $router): void
    {
        $controller = OwnerPortalController::class;

        foreach (['/v1/owner', '/owner'] as $prefix) {
            $router->post("{$prefix}/auth/login", [$controller, 'login']);
            $router->get("{$prefix}/me", [$controller, 'me']);
            $router->get("{$prefix}/dashboard", [$controller, 'dashboard']);
            $router->get("{$prefix}/devices", [$controller, 'devices']);
        }
    }
}
