<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Conflicts;

use MizaCloud\Core\Container\Container;
use MizaCloud\Core\Database\Connection;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Core\Modules\ModuleInterface;
use MizaCloud\Core\Router\Router;
use MizaCloud\Modules\Conflicts\Controllers\ConflictController;
use MizaCloud\Modules\Conflicts\Repositories\ConflictRepository;
use MizaCloud\Modules\Conflicts\Services\ConflictService;

final class ConflictsModule implements ModuleInterface
{
    public function name(): string { return 'conflicts'; }

    public function register(Container $container): void
    {
        $container->singleton(ConflictRepository::class, static fn ($c) => new ConflictRepository($c->get(Connection::class)));
        $container->singleton(ConflictService::class, static fn ($c) => new ConflictService($c->get(ConflictRepository::class)));
        $container->singleton(ConflictController::class, static fn ($c) => new ConflictController($c->get(ResponseBuilder::class), $c->get(ConflictService::class)));
    }

    public function routes(Router $router): void {}
}
