<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Auth;

use MizaCloud\Core\Config\Config;
use MizaCloud\Core\Container\Container;
use MizaCloud\Core\Database\Connection;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Core\Logging\Logger;
use MizaCloud\Core\Modules\ModuleInterface;
use MizaCloud\Core\Router\Router;
use MizaCloud\Modules\Auth\Controllers\AuthController;
use MizaCloud\Modules\Auth\Repositories\AuthRepository;
use MizaCloud\Modules\Auth\Services\AuthService;
use MizaCloud\Modules\Auth\Services\JwtService;
use MizaCloud\Modules\Auth\Services\RoleScopeResolver;

final class AuthModule implements ModuleInterface
{
    public function name(): string
    {
        return 'auth';
    }

    public function register(Container $container): void
    {
        $container->singleton(RoleScopeResolver::class, static fn () => new RoleScopeResolver());

        $container->singleton(JwtService::class, static function (Container $c): JwtService {
            $config = $c->get(Config::class)->get('jwt', []);
            if (!is_array($config)) {
                $config = [];
            }

            return new JwtService(
                secret: (string) ($config['secret'] ?? ''),
                issuer: (string) ($config['issuer'] ?? 'api.mizapos.com'),
                accessTtl: (int) ($config['access_ttl'] ?? 900),
            );
        });

        $container->singleton(AuthRepository::class, static fn ($c) => new AuthRepository($c->get(Connection::class)));

        $container->singleton(AuthService::class, static function (Container $c): AuthService {
            $jwtConfig = $c->get(Config::class)->get('jwt', []);
            if (!is_array($jwtConfig)) {
                $jwtConfig = [];
            }

            return new AuthService(
                repository: $c->get(AuthRepository::class),
                jwt: $c->get(JwtService::class),
                scopes: $c->get(RoleScopeResolver::class),
                logger: $c->get(Logger::class),
                accessTtl: (int) ($jwtConfig['access_ttl'] ?? 900),
                refreshTtl: (int) ($jwtConfig['refresh_ttl'] ?? 2592000),
            );
        });

        $container->singleton(AuthController::class, static fn ($c) => new AuthController(
            $c->get(ResponseBuilder::class),
            $c->get(AuthService::class),
        ));
    }

    public function routes(Router $router): void
    {
        $controller = AuthController::class;

        foreach ($this->prefixes() as $prefix) {
            $router->post("{$prefix}/login", [$controller, 'login']);
            $router->post("{$prefix}/token/refresh", [$controller, 'refresh']);
            $router->post("{$prefix}/logout", [$controller, 'logout']);
            $router->get("{$prefix}/me", [$controller, 'me']);
        }
    }

    /** @return list<string> */
    private function prefixes(): array
    {
        return ['/v1/auth', '/auth'];
    }
}
