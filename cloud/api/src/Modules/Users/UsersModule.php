<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Users;

use MizaCloud\Core\Container\Container;
use MizaCloud\Core\Database\Connection;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Core\Modules\ModuleInterface;
use MizaCloud\Core\Router\Router;
use MizaCloud\Modules\Users\Controllers\UserController;
use MizaCloud\Modules\Users\Repositories\UserRepository;
use MizaCloud\Modules\Users\Services\UserService;

final class UsersModule implements ModuleInterface
{
    public function name(): string { return 'users'; }

    public function register(Container $container): void
    {
        $container->singleton(UserRepository::class, static fn ($c) => new UserRepository($c->get(Connection::class)));
        $container->singleton(UserService::class, static fn ($c) => new UserService($c->get(UserRepository::class)));
        $container->singleton(UserController::class, static fn ($c) => new UserController($c->get(ResponseBuilder::class), $c->get(UserService::class)));
    }

    public function routes(Router $router): void {}
}
