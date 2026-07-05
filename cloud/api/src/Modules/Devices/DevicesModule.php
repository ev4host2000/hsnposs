<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Devices;

use MizaCloud\Core\Config\Config;
use MizaCloud\Core\Container\Container;
use MizaCloud\Core\Database\Connection;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Core\Logging\Logger;
use MizaCloud\Core\Modules\ModuleInterface;
use MizaCloud\Core\Router\Router;
use MizaCloud\Modules\Auth\Services\JwtService;
use MizaCloud\Modules\Auth\Services\RoleScopeResolver;
use MizaCloud\Modules\Devices\Controllers\DeviceController;
use MizaCloud\Modules\Devices\Repositories\DeviceRepository;
use MizaCloud\Modules\Devices\Services\DeviceService;
use MizaCloud\Modules\Devices\Services\DeviceTokenService;
use MizaCloud\Modules\Devices\Support\BearerToken;

final class DevicesModule implements ModuleInterface
{
    public function name(): string
    {
        return 'devices';
    }

    public function register(Container $container): void
    {
        $container->singleton(DeviceRepository::class, static fn ($c) => new DeviceRepository($c->get(Connection::class)));

        $container->singleton(BearerToken::class, static fn ($c) => new BearerToken(
            $c->get(JwtService::class),
            $c->get(DeviceRepository::class),
        ));

        $container->singleton(DeviceTokenService::class, static function (Container $c): DeviceTokenService {
            $jwtConfig = $c->get(Config::class)->get('jwt', []);
            if (!is_array($jwtConfig)) {
                $jwtConfig = [];
            }

            return new DeviceTokenService(
                repository: $c->get(DeviceRepository::class),
                jwt: $c->get(JwtService::class),
                accessTtl: (int) ($jwtConfig['access_ttl'] ?? 900),
                refreshTtl: (int) ($jwtConfig['refresh_ttl'] ?? 2592000),
            );
        });

        $container->singleton(DeviceService::class, static fn ($c) => new DeviceService(
            repository: $c->get(DeviceRepository::class),
            tokens: $c->get(DeviceTokenService::class),
            bearer: $c->get(BearerToken::class),
            scopes: $c->get(RoleScopeResolver::class),
            logger: $c->get(Logger::class),
        ));

        $container->singleton(DeviceController::class, static fn ($c) => new DeviceController(
            $c->get(ResponseBuilder::class),
            $c->get(DeviceService::class),
        ));
    }

    public function routes(Router $router): void
    {
        $controller = DeviceController::class;

        foreach ($this->prefixes() as $prefix) {
            $router->post("{$prefix}/register", [$controller, 'register']);
            $router->post("{$prefix}/heartbeat", [$controller, 'heartbeat']);
            $router->get("{$prefix}/me", [$controller, 'me']);
        }
    }

    /** @return list<string> */
    private function prefixes(): array
    {
        return ['/v1/devices', '/devices'];
    }
}
