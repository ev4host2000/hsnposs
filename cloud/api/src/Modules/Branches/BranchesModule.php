<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Branches;

use MizaCloud\Core\Container\Container;
use MizaCloud\Core\Database\Connection;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Core\Modules\ModuleInterface;
use MizaCloud\Core\Router\Router;
use MizaCloud\Modules\Branches\Controllers\BranchController;
use MizaCloud\Modules\Branches\Repositories\BranchRepository;
use MizaCloud\Modules\Branches\Services\BranchService;

final class BranchesModule implements ModuleInterface
{
    public function name(): string { return 'branches'; }

    public function register(Container $container): void
    {
        $container->singleton(BranchRepository::class, static fn ($c) => new BranchRepository($c->get(Connection::class)));
        $container->singleton(BranchService::class, static fn ($c) => new BranchService($c->get(BranchRepository::class)));
        $container->singleton(BranchController::class, static fn ($c) => new BranchController($c->get(ResponseBuilder::class), $c->get(BranchService::class)));
    }

    public function routes(Router $router): void {}
}
